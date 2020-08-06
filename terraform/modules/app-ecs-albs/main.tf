/**
* ## Module: app-ecs-albs
*
* Load balancer for Prometheus
*
*/

variable "aws_region" {
  type        = string
  description = "AWS region"
}

variable "remote_state_bucket" {
  type        = string
  description = "S3 bucket we store our terraform state in"
}

variable "environment" {
  type        = string
  description = "Unique name for this collection of resources"
}

variable "zone_id" {
  type        = string
  description = "Route 53 zone ID for registering public DNS records"
}

variable "subnets" {
  type        = list(string)
  description = "Subnets to attach load balancers to"
}

variable "prometheus_count" {
  type        = string
  description = "Number of prometheus instances to create listener rules and target groups for"
  default     = "3"
}

# locals
# --------------------------------------------------------------

locals {
  default_tags = {
    Terraform   = "true"
    Project     = "app-ecs-albs"
    Source      = "github.com/alphagov/prometheus-aws-configuration-beta"
    Environment = var.environment
  }

  prom_records_count = var.prometheus_count

  # data.aws_route_53.XXX.name has a trailing dot which we remove with replace() to make ACM happy
  subdomain = replace(data.aws_route53_zone.public_zone.name, "/\\.$/", "")
  vpc_id    = data.aws_subnet.first_subnet.vpc_id
}

## Data sources

data "terraform_remote_state" "infra_networking" {
  backend = "s3"

  config = {
    bucket = var.remote_state_bucket
    key    = "infra-networking-modular.tfstate"
    region = var.aws_region
  }
}

data "terraform_remote_state" "infra_security_groups" {
  backend = "s3"

  config = {
    bucket = var.remote_state_bucket
    key    = "infra-security-groups-modular.tfstate"
    region = var.aws_region
  }
}

data "aws_route53_zone" "public_zone" {
  zone_id = var.zone_id
}

data "aws_subnet" "first_subnet" {
  id = var.subnets[0]
}

######################################################################
# ----- prometheus public ALB -------
######################################################################

# AWS should manage the certificate renewal automatically
# https://docs.aws.amazon.com/acm/latest/userguide/managed-renewal.html
# If this fails, AWS will email associated with the AWS account
resource "aws_acm_certificate" "prometheus_cert" {
  domain_name       = "prom.${local.subdomain}"
  validation_method = "DNS"

  subject_alternative_names = aws_route53_record.prom_alias.*.fqdn

  lifecycle {
    # We can't destroy a certificate that's in use, and we can't stop
    # using it until the new one is ready.  Hence
    # create_before_destroy here.
    create_before_destroy = true
  }
}

resource "aws_route53_record" "prometheus_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.prometheus_cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  name    = each.value.name
  records = [each.value.record]
  type    = each.value.type
  zone_id = var.zone_id
  ttl     = 60

  depends_on = [aws_acm_certificate.prometheus_cert]
}

resource "aws_acm_certificate_validation" "prometheus_cert" {
  certificate_arn         = aws_acm_certificate.prometheus_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.prometheus_cert_validation : record.fqdn]
}

resource "aws_route53_record" "prom_alias" {
  count = local.prom_records_count

  zone_id = var.zone_id
  name    = "prom-${count.index + 1}"
  type    = "A"

  alias {
    name                   = aws_lb.prometheus_alb.dns_name
    zone_id                = aws_lb.prometheus_alb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_lb" "prometheus_alb" {
  name               = "${var.environment}-prometheus-alb"
  internal           = false
  load_balancer_type = "application"

  security_groups = [data.terraform_remote_state.infra_security_groups.outputs.prometheus_alb_sg_id]

  subnets = var.subnets

  tags = merge(
    local.default_tags,
    {
      Name    = "${var.environment}-prometheus-alb"
      Service = "observe-prometheus"
    },
  )
}

resource "aws_lb_listener" "prometheus_listener_http" {
  load_balancer_arn = aws_lb.prometheus_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "prometheus_listener_https" {
  load_balancer_arn = aws_lb.prometheus_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = aws_acm_certificate_validation.prometheus_cert.certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Not found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "prom_listener_https" {
  count = var.prometheus_count

  listener_arn = aws_lb_listener.prometheus_listener_https.arn
  priority     = 100 + count.index

  action {
    type             = "forward"
    target_group_arn = element(aws_lb_target_group.prometheus_tg.*.arn, count.index)
  }

  condition {
    host_header {
      values = ["prom-${count.index + 1}.*"]
    }
  }
}

resource "aws_lb_target_group" "prometheus_tg" {
  count = var.prometheus_count

  name                 = "${var.environment}-prom-${count.index + 1}-tg"
  port                 = 80
  protocol             = "HTTP"
  vpc_id               = local.vpc_id
  deregistration_delay = 30

  health_check {
    interval            = "10"
    path                = "/health" # static health check on nginx auth proxy
    matcher             = "200"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = "5"
  }
}

## Outputs

output "prom_public_record_fqdns" {
  value       = aws_route53_record.prom_alias.*.fqdn
  description = "Prometheus public DNS FQDNs"
}

output "prometheus_target_group_ids" {
  value       = aws_lb_target_group.prometheus_tg.*.arn
  description = "Prometheus target group IDs"
}

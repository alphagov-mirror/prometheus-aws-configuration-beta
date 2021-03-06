/**
* ## module: infra-security-groups
*
* Central module to manage all security groups.
*
* This is done in a single module to reduce conflicts
* and cascade issues.
*
*/

variable "aws_region" {
  type        = string
  description = "The AWS region to use."
}

variable "remote_state_bucket" {
  type        = string
  description = "S3 bucket we store our terraform state in"
}

variable "environment" {
  type        = string
  description = "Unique name for this collection of resources"
}

# locals
# --------------------------------------------------------------

locals {
  default_tags = {
    Terraform   = "true"
    Project     = "infra-security-groups"
    Source      = "github.com/alphagov/prometheus-aws-configuration-beta"
    Environment = var.environment
  }
}

# Resources
# --------------------------------------------------------------

## Data sources

data "terraform_remote_state" "infra_networking" {
  backend = "s3"

  config = {
    bucket = var.remote_state_bucket
    key    = "infra-networking-modular.tfstate"
    region = var.aws_region
  }
}

resource "aws_security_group" "prometheus_alb" {
  name        = "${var.environment}-prometheus-alb"
  vpc_id      = data.terraform_remote_state.infra_networking.outputs.vpc_id
  description = "Controls ingress and egress for prometheus ALB"

  tags = merge(
    local.default_tags,
    {
      Name    = "prometheus-alb",
      Service = "observe-prometheus",
    },
  )
}

# We allow all IPs to access the ALB as Prometheus is fronted by an nginx which controls access to either approved IP
# addresses, or users with basic auth creds
resource "aws_security_group_rule" "ingress_from_public_http_to_prometheus_alb" {
  security_group_id = aws_security_group.prometheus_alb.id
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "ingress_from_public_https_to_prometheus_alb" {
  security_group_id = aws_security_group.prometheus_alb.id
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "egress_from_prometheus_alb_to_prometheus_ec2" {
  security_group_id        = aws_security_group.prometheus_alb.id
  type                     = "egress"
  to_port                  = 80
  from_port                = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.prometheus_ec2.id
}

resource "aws_security_group" "prometheus_ec2" {
  name        = "${var.environment}-prometheus-ec2"
  vpc_id      = data.terraform_remote_state.infra_networking.outputs.vpc_id
  description = "Controls ingress and egress for prometheus EC2 instances"

  tags = merge(
    local.default_tags,
    {
      Name    = "prometheus-ec2",
      Service = "observe-prometheus",
    },
  )
}

resource "aws_security_group_rule" "ingress_from_prometheus_alb_to_prometheus_ec2" {
  security_group_id        = aws_security_group.prometheus_ec2.id
  type                     = "ingress"
  to_port                  = 80
  from_port                = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.prometheus_alb.id
}

resource "aws_security_group_rule" "ingress_from_prometheus_ec2_to_prometheus_ec2" {
  security_group_id        = aws_security_group.prometheus_ec2.id
  type                     = "ingress"
  to_port                  = 9090
  from_port                = 9090
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.prometheus_ec2.id
}

resource "aws_security_group_rule" "ingress_from_prometheus_to_prometheus_node_exporter" {
  security_group_id        = aws_security_group.prometheus_ec2.id
  type                     = "ingress"
  to_port                  = 9100
  from_port                = 9100
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.prometheus_ec2.id
}

# This rule allows all egress out of prometheus_ec2. This is for the following purposes:
# - downloading packages from package repos
# - calling AWS APIs such as SSM, S3 and EC2
# - scraping alertmanager on port 9093
# - sending alerts to alertmanager on port 9093
# - scraping external targets that run on the PaaS
# - scraping itself and other promethis on port 9090
# - scraping node exporters on port 9100
resource "aws_security_group_rule" "egress_from_prometheus_ec2_to_all" {
  security_group_id = aws_security_group.prometheus_ec2.id
  type              = "egress"
  to_port           = 0
  from_port         = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

## Outputs

output "prometheus_ec2_sg_id" {
  value       = aws_security_group.prometheus_ec2.id
  description = "security group prometheus_ec2 ID"
}

output "prometheus_alb_sg_id" {
  value       = aws_security_group.prometheus_alb.id
  description = "security group prometheus_alb ID"
}

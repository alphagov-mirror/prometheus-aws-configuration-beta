## Providers

terraform {
  required_version = "= 0.11.10"

  backend "s3" {
    bucket = "prometheus-production"
    key    = "app-ecs-albs-modular.tfstate"
  }
}

provider "aws" {
  version = "~> 1.14.1"
  region  = "${var.aws_region}"
}

variable "aws_region" {
  type        = "string"
  description = "AWS region"
  default     = "eu-west-1"
}

variable "remote_state_bucket" {
  type        = "string"
  description = "S3 bucket we store our terraform state in"
  default     = "prometheus-production"
}

variable "stack_name" {
  type        = "string"
  description = "Unique name for this collection of resources"
  default     = "production"
}

variable "project" {
  type        = "string"
  description = "Project name for tag"
  default     = "app-ecs-albs-production"
}

module "app-ecs-albs" {
  source = "../../modules/app-ecs-albs/"

  aws_region          = "${var.aws_region}"
  stack_name          = "${var.stack_name}"
  remote_state_bucket = "${var.remote_state_bucket}"
  project             = "${var.project}"
}

output "monitoring_external_tg" {
  value       = "${module.app-ecs-albs.monitoring_external_tg}"
  description = "Monitoring external target group"
}

output "monitoring_internal_tg" {
  value       = "${module.app-ecs-albs.monitoring_internal_tg}"
  description = "External Alertmanager ALB target group"
}

output "paas_proxy_tg" {
  value       = "${module.app-ecs-albs.paas_proxy_tg}"
  description = "Paas proxy target group"
}

output "prom_public_record_fqdns" {
  value       = "${module.app-ecs-albs.prom_public_record_fqdns}"
  description = "Prometheus public DNS FQDNs"
}

output "alerts_public_record_fqdns" {
  value       = "${module.app-ecs-albs.alerts_public_record_fqdns}"
  description = "Alertmanagers public DNS FQDNs"
}

output "alerts_private_record_fqdns" {
  value       = "${module.app-ecs-albs.alerts_private_record_fqdns}"
  description = "Alertmanagers private DNS FQDNs"
}
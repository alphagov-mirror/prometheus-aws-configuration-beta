/**
* ## Module: app-ecs-services
*
* Create services and task definitions for the ECS cluster
*
*/

variable "aws_region" {
  type        = string
  description = "AWS region"
  default     = "eu-west-1"
}

variable "cidr_admin_whitelist" {
  description = "CIDR ranges permitted to communicate with administrative endpoints"
  type        = list(string)

  default = [
    "213.86.153.212/32",
    "213.86.153.213/32",
    "213.86.153.214/32",
    "213.86.153.235/32",
    "213.86.153.236/32",
    "213.86.153.237/32",
    "85.133.67.244/32",
  ]
}

variable "remote_state_bucket" {
  type        = string
  description = "S3 bucket we store our terraform state in"
  default     = "ecs-monitoring"
}

variable "stack_name" {
  type        = string
  description = "Unique name for this collection of resources"
  default     = "ecs-monitoring"
}

variable "observe_cronitor" {
  type        = string
  description = "URL to send Observe heartbeats to"
  default     = ""
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

data "terraform_remote_state" "infra_security_groups" {
  backend = "s3"

  config = {
    bucket = var.remote_state_bucket
    key    = "infra-security-groups-modular.tfstate"
    region = var.aws_region
  }
}

data "terraform_remote_state" "app_ecs_albs" {
  backend = "s3"

  config = {
    bucket = var.remote_state_bucket
    key    = "app-ecs-albs-modular.tfstate"
    region = var.aws_region
  }
}

## Resources

resource "aws_cloudwatch_log_group" "task_logs" {
  name              = var.stack_name
  retention_in_days = 7
}

## Outputs

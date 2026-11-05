variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "The AWS region to deploy resources into"
}

variable "ssh_key_name" {
  type        = string
  description = "Name of the EC2 Key Pair to attach to instances for SSH access"
  default     = ""
}

variable "name_prefix" {
  type        = string
  default     = "retrograde"
  description = "Prefix for resource names (must be lowercase)"
}

variable "domain_name" {
  description = "Custom domain name"
  type        = string
  default     = ""
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM SSL/TLS certificate in us-east-1"
  type        = string
  default     = ""
}

variable "budget_limit_amount" {
  description = "Monthly budget limit in USD before triggering alerts"
  type        = string
  default     = "5.0"
}

variable "budget_alert_email" {
  description = "Email address for AWS Budget cost alerts"
  type        = string
  default     = ""
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "enable_login_scaling" {
  type        = bool
  default     = false
  description = "Enable demo scale-out above the active-login threshold. Sessions remain instance-local."
}

variable "scale_threshold" {
  type    = number
  default = 12
  validation {
    condition     = var.scale_threshold >= 1 && floor(var.scale_threshold) == var.scale_threshold
    error_message = "scale_threshold must be a positive integer."
  }
}

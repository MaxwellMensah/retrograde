variable "region" {
  description = "AWS region (matches your existing provider block)"
  type        = string
  default     = "us-east-1"
}

variable "vpc_name" {
  description = "Name tag of your EXISTING VPC (same lookup as terraform-aws-app/main.tf)"
  type        = string
  default     = "mygroupvpc"
}

variable "subnet_ids" {
  description = "Leave empty to auto-pick one subnet per Availability Zone in the VPC. Or list at least two PUBLIC subnet ids."
  type        = list(string)
  default     = []
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "retrograde"
}

variable "asg_name" {
  description = "Name of the Auto Scaling Group. app.py publishes its metrics under this name."
  type        = string
  default     = "retrograde-asg"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "min_size" {
  description = "Instances running when nobody is logged in"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Upper limit. Must be 3 or more: 13-24 users -> 2 instances, 25+ users -> 3 instances."
  type        = number
  default     = 3
}

variable "login_threshold" {
  description = "Scale out when MORE than this many users are logged in (12 means the 13th triggers it)"
  type        = number
  default     = 12
}

variable "enable_scale_in" {
  description = "Also scale back down to the minimum once logins fall below scale_in_threshold for 5 minutes"
  type        = bool
  default     = true
}

variable "scale_in_threshold" {
  type    = number
  default = 8
}

variable "app_dir" {
  description = "Folder containing app.py and templates/retro_test.html. Empty = the folder above this one (the repo root)."
  type        = string
  default     = ""
}

variable "instance_profile_name" {
  description = "Only if your account does NOT allow creating IAM roles: name of an existing instance profile that can read S3 and call cloudwatch:PutMetricData. Empty = Terraform creates one."
  type        = string
  default     = ""
}

variable "allowed_cidr" {
  description = "Who may open the site on port 80"
  type        = string
  default     = "0.0.0.0/0"
}

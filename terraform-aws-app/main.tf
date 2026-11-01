# ---------------------------------------------------------------------------
# Project #Retrograde - one-shot test environment
#   ALB -> Auto Scaling Group (EC2 running app.py) -> CloudWatch alarm on logins
#
#   terraform init && terraform apply     # build everything
#   terraform destroy                     # remove everything when you are done
#
# The app code is uploaded to a private S3 bucket and every instance pulls it at boot.
# ---------------------------------------------------------------------------
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "retrograde"
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "me" {}

locals {
  app_dir        = var.app_dir != "" ? var.app_dir : "${path.module}/.."
  bucket_name    = "${var.name_prefix}-app-${data.aws_caller_identity.me.account_id}-${var.region}"
  create_profile = var.instance_profile_name == ""
}

# ---------------------------------------------------------------------------
# 1. Your EXISTING VPC and its subnets (one subnet per Availability Zone)
# ---------------------------------------------------------------------------
data "aws_vpc" "this" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }
  filter {
    name   = "map-public-ip-on-launch"
    values = ["true"]
  }
}

data "aws_subnets" "all" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }
}

locals {
  candidate_subnet_ids = length(data.aws_subnets.public.ids) >= 2 ? data.aws_subnets.public.ids : data.aws_subnets.all.ids
}

data "aws_subnet" "candidate" {
  for_each = toset(local.candidate_subnet_ids)
  id       = each.value
}

locals {
  subnets_by_az = { for s in data.aws_subnet.candidate : s.availability_zone => s.id... }
  subnet_ids    = length(var.subnet_ids) > 0 ? var.subnet_ids : [for az in sort(keys(local.subnets_by_az)) : local.subnets_by_az[az][0]]
}

# ---------------------------------------------------------------------------
# 2. App bundle in S3 (uploaded from your repo folder; re-uploaded when the files change)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "app" {
  bucket        = local.bucket_name
  force_destroy = true # lets "terraform destroy" delete the bucket even though it holds files
}

resource "aws_s3_bucket_public_access_block" "app" {
  bucket                  = aws_s3_bucket.app.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "app_py" {
  bucket = aws_s3_bucket.app.id
  key    = "app/app.py"
  source = "${local.app_dir}/app.py"
  etag   = filemd5("${local.app_dir}/app.py")
}

resource "aws_s3_object" "page" {
  bucket       = aws_s3_bucket.app.id
  key          = "app/templates/retro_test.html"
  source       = "${local.app_dir}/templates/retro_test.html"
  etag         = filemd5("${local.app_dir}/templates/retro_test.html")
  content_type = "text/html"
}

# ---------------------------------------------------------------------------
# 3. Permissions for the instances (read the bundle, publish login metrics, read ASG size)
#    Skipped if you pass instance_profile_name (accounts that forbid creating IAM roles).
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "app" {
  statement {
    sid       = "ReadAppBundle"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.app.arn}/app/*"]
  }
  statement {
    sid       = "PublishLoginMetrics"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["Retrograde/Portal"]
    }
  }
  statement {
    sid       = "ReadAsgSize"
    actions   = ["autoscaling:DescribeAutoScalingGroups"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "ec2" {
  count              = local.create_profile ? 1 : 0
  name               = "${var.name_prefix}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy" "app" {
  count  = local.create_profile ? 1 : 0
  name   = "${var.name_prefix}-app-access"
  role   = aws_iam_role.ec2[0].id
  policy = data.aws_iam_policy_document.app.json
}

# lets you open a shell on an instance from the AWS console (Session Manager) - no SSH key needed
resource "aws_iam_role_policy_attachment" "ssm" {
  count      = local.create_profile ? 1 : 0
  role       = aws_iam_role.ec2[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  count = local.create_profile ? 1 : 0
  name  = "${var.name_prefix}-ec2-profile"
  role  = aws_iam_role.ec2[0].name
}

locals {
  profile_name = local.create_profile ? aws_iam_instance_profile.ec2[0].name : var.instance_profile_name
}

# ---------------------------------------------------------------------------
# 4. Security groups: the internet reaches the ALB on 80; only the ALB reaches the app on 8000
# ---------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Retrograde load balancer"
  vpc_id      = data.aws_vpc.this.id

  ingress {
    description = "HTTP from the allowed range"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "web" {
  name        = "${var.name_prefix}-web-sg"
  description = "Retrograde app instances"
  vpc_id      = data.aws_vpc.this.id

  ingress {
    description     = "App port, from the load balancer only"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------------------------------------------------------------------
# 5. Application Load Balancer. Stickiness keeps one user on one instance,
#    so the per-instance login counts add up correctly.
# ---------------------------------------------------------------------------
resource "aws_lb" "web" {
  name               = "${var.name_prefix}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.subnet_ids

  lifecycle {
    precondition {
      condition     = length(local.subnet_ids) >= 2
      error_message = "The load balancer needs subnets in at least 2 Availability Zones. Found ${length(local.subnet_ids)} in VPC '${var.vpc_name}'. Set var.subnet_ids."
    }
  }
}

resource "aws_lb_target_group" "web" {
  name                 = "${var.name_prefix}-tg"
  port                 = 8000
  protocol             = "HTTP"
  vpc_id               = data.aws_vpc.this.id
  deregistration_delay = 30

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = true
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# ---------------------------------------------------------------------------
# 6. Launch template + Auto Scaling Group
# ---------------------------------------------------------------------------
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_launch_template" "web" {
  name_prefix            = "${var.name_prefix}-web-"
  image_id               = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  update_default_version = true

  iam_instance_profile {
    name = local.profile_name
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web.id]
    delete_on_termination       = true
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    bucket    = aws_s3_bucket.app.id
    region    = var.region
    asg_name  = var.asg_name
    threshold = var.login_threshold
    code_hash = md5("${aws_s3_object.app_py.etag}${aws_s3_object.page.etag}")
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.name_prefix}-web"
    }
  }

  depends_on = [aws_s3_object.app_py, aws_s3_object.page]
}

resource "aws_autoscaling_group" "web" {
  name                      = var.asg_name
  min_size                  = var.min_size
  max_size                  = var.max_size
  desired_capacity          = var.min_size
  vpc_zone_identifier       = local.subnet_ids
  target_group_arns         = [aws_lb_target_group.web.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 300
  metrics_granularity       = "1Minute"
  enabled_metrics           = ["GroupDesiredCapacity", "GroupInServiceInstances", "GroupTotalInstances"]

  # make "terraform apply" wait until the first instance is healthy behind the load balancer
  wait_for_elb_capacity     = var.min_size
  wait_for_capacity_timeout = "15m"

  launch_template {
    id      = aws_launch_template.web.id
    version = aws_launch_template.web.latest_version
  }

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-web"
    propagate_at_launch = true
  }

  lifecycle {
    ignore_changes = [desired_capacity] # the scaling policy owns this after creation
  }
}

# ---------------------------------------------------------------------------
# 7. The trigger: CloudWatch alarm on the ActiveLogins metric that app.py publishes.
#    More than 12 users (the 13th) -> 2 instances; more than 24 -> 3 instances.
# ---------------------------------------------------------------------------
resource "aws_autoscaling_policy" "scale_out" {
  name                      = "${var.name_prefix}-scale-out"
  autoscaling_group_name    = aws_autoscaling_group.web.name
  policy_type               = "StepScaling"
  adjustment_type           = "ExactCapacity"
  metric_aggregation_type   = "Maximum"
  estimated_instance_warmup = 120

  step_adjustment {
    metric_interval_lower_bound = "0"
    metric_interval_upper_bound = tostring(var.login_threshold)
    scaling_adjustment          = 2
  }
  step_adjustment {
    metric_interval_lower_bound = tostring(var.login_threshold)
    scaling_adjustment          = 3
  }
}

resource "aws_cloudwatch_metric_alarm" "logins_high" {
  alarm_name          = "${var.name_prefix}-logins-high"
  alarm_description   = "More than ${var.login_threshold} users logged in across the fleet"
  namespace           = "Retrograde/Portal"
  metric_name         = "ActiveLogins"
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.web.name }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = var.login_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_autoscaling_policy.scale_out.arn]
}

resource "aws_autoscaling_policy" "scale_in" {
  count                   = var.enable_scale_in ? 1 : 0
  name                    = "${var.name_prefix}-scale-in"
  autoscaling_group_name  = aws_autoscaling_group.web.name
  policy_type             = "StepScaling"
  adjustment_type         = "ExactCapacity"
  metric_aggregation_type = "Maximum"

  step_adjustment {
    metric_interval_upper_bound = "0"
    scaling_adjustment          = var.min_size
  }
}

resource "aws_cloudwatch_metric_alarm" "logins_low" {
  count               = var.enable_scale_in ? 1 : 0
  alarm_name          = "${var.name_prefix}-logins-low"
  alarm_description   = "Fewer than ${var.scale_in_threshold} users logged in for 5 minutes"
  namespace           = "Retrograde/Portal"
  metric_name         = "ActiveLogins"
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.web.name }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 5
  threshold           = var.scale_in_threshold
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_autoscaling_policy.scale_in[0].arn]
}
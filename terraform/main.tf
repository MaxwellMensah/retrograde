terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "me" {}

# 1. Fetch your existing VPC named "mygroupvpc"
data "aws_vpc" "this" {
  filter {
    name   = "tag:Name"
    values = ["mygroupvpc"]
  }
}

# 2. Fetch your specific subnets "Subnet-1" and "Subnet-2" inside your VPC
data "aws_subnets" "selected" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }
  filter {
    name   = "tag:Name"
    values = ["Subnet-1", "Subnet-2"]
  }
}

# 4. Fetch the AWS-managed prefix list for CloudFront Origin-Facing IPs
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# 5. Fetch latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------------------------------------------------------------------------
# 6. Security Group for ALB (Restricted strictly to CloudFront Managed Prefix List)
# ---------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "Allow inbound HTTP strictly from CloudFront"
  vpc_id      = data.aws_vpc.this.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------------------------------------------------------------------
# 7. Application Load Balancer & Target Group
# ---------------------------------------------------------------------------
resource "aws_lb" "web" {
  name               = "${var.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.selected.ids
}

resource "aws_lb_target_group" "web" {
  name        = "${var.name_prefix}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.this.id
  target_type = "instance"

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 3600
    enabled         = true
  }

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "web" {
  load_balancer_arn = aws_lb.web.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# ---------------------------------------------------------------------------
# 8. IAM Role & Profile for EC2 to read app files and images from S3
# ---------------------------------------------------------------------------
resource "aws_iam_role" "ec2_s3_reader" {
  name = "${var.name_prefix}-ec2-s3-reader-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "s3_read_policy" {
  name = "${var.name_prefix}-s3-read-policy"
  role = aws_iam_role.ec2_s3_reader.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.static_assets.arn,
          "${aws_s3_bucket.static_assets.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2_s3_reader.name
}

# Attach AmazonSSMManagedInstanceCore so you can connect via SSM without SSH keys
resource "aws_iam_role_policy_attachment" "ssm_server" {
  role       = aws_iam_role.ec2_s3_reader.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


# ---------------------------------------------------------------------------
# 9. Launch Template & Auto Scaling Group
# ---------------------------------------------------------------------------
resource "aws_launch_template" "web" {
  name_prefix   = "${var.name_prefix}-lt-"
  image_id      = data.aws_ami.amazon_linux_2023.id
  instance_type = var.instance_type
  key_name      = var.ssh_key_name != "" ? var.ssh_key_name : null

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web.id]
  }

  iam_instance_profile {
    arn = aws_iam_instance_profile.ec2_profile.arn
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  user_data = base64encode(templatefile("${path.module}/bootstrap.sh.tftpl", {
    region         = var.aws_region
    bucket         = aws_s3_bucket.static_assets.id
    release_hash   = local.release_hash
    threshold      = var.scale_threshold
    logging_script = file("${path.module}/install-logging.sh")
    log_group      = aws_cloudwatch_log_group.app_logs.name
  }))

}

resource "aws_autoscaling_group" "web" {
  name_prefix = "${var.name_prefix}-asg-"
  depends_on = [
    aws_iam_role_policy.s3_read_policy,
    aws_iam_role_policy.app_metrics,
    aws_iam_role_policy.app_log_delivery,
    aws_iam_role_policy_attachment.ssm_server,
    aws_s3_object.app_py,
    aws_s3_object.requirements,
    aws_s3_object.template_files,
    aws_s3_object.static_files,
    aws_s3_object.image_files,
    aws_lb_listener.web,
  ]
  health_check_type         = "ELB"
  health_check_grace_period = 600
  desired_capacity          = 1
  max_size                  = 2
  min_size                  = 1
  target_group_arns         = [aws_lb_target_group.web.arn]
  vpc_zone_identifier       = data.aws_subnets.selected.ids

  launch_template {
    id      = aws_launch_template.web.id
    version = tostring(aws_launch_template.web.latest_version)
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 100
      max_healthy_percentage = 200
      instance_warmup        = 120
      skip_matching          = true
    }
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-instance"
    propagate_at_launch = true
  }
}

# ---------------------------------------------------------------------------
# 10. S3 Bucket for Static Assets, Images, and App Files with OAC
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "static_assets" {
  bucket        = "${var.name_prefix}-static-assets-${data.aws_caller_identity.me.account_id}-${var.aws_region}"
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "static_assets" {
  bucket                  = aws_s3_bucket.static_assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "s3_oac" {
  name                              = "${var.name_prefix}-s3-oac"
  description                       = "Origin Access Control for static assets S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_iam_policy_document" "s3_oac_policy" {
  statement {
    sid       = "AllowCloudFrontOAC"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.static_assets.arn}/static/*", "${aws_s3_bucket.static_assets.arn}/images/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.cdn.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "static_assets" {
  bucket = aws_s3_bucket.static_assets.id
  policy = data.aws_iam_policy_document.s3_oac_policy.json
}

# Sync local static files to S3
resource "aws_s3_object" "static_files" {
  for_each = fileset("${path.module}/../static", "**")

  bucket        = aws_s3_bucket.static_assets.id
  key           = "static/${each.value}"
  source        = "${path.module}/../static/${each.value}"
  etag          = filemd5("${path.module}/../static/${each.value}")
  content_type  = lookup(local.mime_types, lower(element(reverse(split(".", each.value)), 0)), "application/octet-stream")
  cache_control = "public, max-age=60"

}

# Sync local images to S3
resource "aws_s3_object" "image_files" {
  for_each = fileset("${path.module}/../images", "**")

  bucket        = aws_s3_bucket.static_assets.id
  key           = "images/${each.value}"
  source        = "${path.module}/../images/${each.value}"
  etag          = filemd5("${path.module}/../images/${each.value}")
  content_type  = lookup(local.mime_types, lower(element(reverse(split(".", each.value)), 0)), "application/octet-stream")
  cache_control = "public, max-age=60"

}

# Upload local backend code (app.py, requirements.txt, templates) to S3
resource "aws_s3_object" "app_py" {
  bucket = aws_s3_bucket.static_assets.id
  key    = "app/app.py"
  source = "${path.module}/../app.py"
  etag   = filemd5("${path.module}/../app.py")
}

resource "aws_s3_object" "requirements" {
  bucket = aws_s3_bucket.static_assets.id
  key    = "app/requirements.txt"
  source = "${path.module}/../requirements.txt"
  etag   = filemd5("${path.module}/../requirements.txt")
}

resource "aws_s3_object" "template_files" {
  for_each = fileset("${path.module}/../templates", "**")

  bucket = aws_s3_bucket.static_assets.id
  key    = "app/templates/${each.value}"
  source = "${path.module}/../templates/${each.value}"
  etag   = filemd5("${path.module}/../templates/${each.value}")
}

# ---------------------------------------------------------------------------
# 11. CloudFront Distribution (Dual Origin: ALB + S3)
# ---------------------------------------------------------------------------
resource "aws_cloudfront_distribution" "cdn" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "Retrograde CloudFront CDN fronting ALB and S3"
  aliases         = var.domain_name != "" ? [var.domain_name] : []

  lifecycle {
    precondition {
      condition     = var.domain_name == "" || var.acm_certificate_arn != ""
      error_message = "A custom domain requires its ACM certificate in us-east-1."
    }
  }

  origin {
    domain_name = aws_lb.web.dns_name
    origin_id   = "ALBOrigin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  origin {
    domain_name              = aws_s3_bucket.static_assets.bucket_regional_domain_name
    origin_id                = "S3StaticOrigin"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3_oac.id
  }

  default_cache_behavior {
    target_origin_id       = "ALBOrigin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]

    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.viewer.id
    compress                 = true
  }

  ordered_cache_behavior {
    path_pattern           = "/static/*"
    target_origin_id       = "S3StaticOrigin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    min_ttl     = 0
    default_ttl = 60
    max_ttl     = 300
    compress    = true
  }

  ordered_cache_behavior {
    path_pattern           = "/images/*"
    target_origin_id       = "S3StaticOrigin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    min_ttl     = 0
    default_ttl = 60
    max_ttl     = 300
    compress    = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.acm_certificate_arn == "" ? true : false
    acm_certificate_arn            = var.acm_certificate_arn != "" ? var.acm_certificate_arn : null
    ssl_support_method             = var.acm_certificate_arn != "" ? "sni-only" : null
    minimum_protocol_version       = "TLSv1.2_2021"
  }
}

# ---------------------------------------------------------------------------
# 12. CloudWatch Alarms & Log Retention
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/aws/ec2/${var.name_prefix}-app"
  retention_in_days = 7
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.name_prefix}-cpu-utilization-high"
  alarm_description   = "EC2 average CPU utilization is greater than 80%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.web.name }
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.name_prefix}-alb-5xx-errors-high"
  alarm_description   = "Target-generated 5xx responses exceed 5% of routed requests over 60 seconds. Does not include ALB-generated errors."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 5
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "error_rate"
    expression  = "IF(requests > 0, 100 * FILL(errors, 0) / requests, 0)"
    label       = "Target 5xx error rate (%)"
    return_data = true
  }
  metric_query {
    id          = "errors"
    return_data = false
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      period      = 60
      stat        = "Sum"
      dimensions  = { LoadBalancer = aws_lb.web.arn_suffix }
    }
  }
  metric_query {
    id          = "requests"
    return_data = false
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      period      = 60
      stat        = "Sum"
      dimensions  = { LoadBalancer = aws_lb.web.arn_suffix }
    }
  }
}

# ---------------------------------------------------------------------------
# 13. AWS Budgets Alert
# ---------------------------------------------------------------------------
resource "aws_budgets_budget" "cost_limit" {
  count        = var.budget_alert_email != "" ? 1 : 0
  name         = "${var.name_prefix}-free-tier-budget"
  budget_type  = "COST"
  limit_amount = var.budget_limit_amount
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}

# Application-specific deployment configuration.
locals {
  mime_types = {
    css   = "text/css"
    js    = "application/javascript"
    json  = "application/json"
    html  = "text/html"
    ico   = "image/x-icon"
    png   = "image/png"
    jpg   = "image/jpeg"
    jpeg  = "image/jpeg"
    svg   = "image/svg+xml"
    webp  = "image/webp"
    woff  = "font/woff"
    woff2 = "font/woff2"
  }
  # Content changes create a launch-template version and start an ASG refresh.
  release_hash = sha256(jsonencode({
    app          = filesha256("${path.module}/../app.py")
    requirements = filesha256("${path.module}/../requirements.txt")
    templates    = { for f in fileset("${path.module}/../templates", "**") : f => filesha256("${path.module}/../templates/${f}") }
    static       = { for f in fileset("${path.module}/../static", "**") : f => filesha256("${path.module}/../static/${f}") }
    images       = { for f in fileset("${path.module}/../images", "**") : f => filesha256("${path.module}/../images/${f}") }
  }))
}

resource "aws_security_group" "web" {
  name        = "${var.name_prefix}-web-sg"
  description = "Application HTTP from the ALB; administration through SSM"
  vpc_id      = data.aws_vpc.this.id
  ingress {
    from_port       = 80
    to_port         = 80
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

resource "aws_iam_role_policy" "app_metrics" {
  name = "${var.name_prefix}-app-metrics"
  role = aws_iam_role.ec2_s3_reader.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = ["cloudwatch:PutMetricData"]
        Resource  = "*"
        Condition = { StringEquals = { "cloudwatch:namespace" = "Retrograde/Portal" } }
      },
      {
        Effect   = "Allow"
        Action   = ["autoscaling:DescribeAutoScalingGroups", "autoscaling:DescribeAutoScalingInstances"]
        Resource = "*"
      }
    ]
  })
}

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "viewer" {
  name = "Managed-AllViewerExceptHostHeader"
}

# Optional demo scale-out only. No automated scale-in with in-memory sessions.
resource "aws_autoscaling_policy" "login_scale_out" {
  count                  = var.enable_login_scaling ? 1 : 0
  name                   = "${var.name_prefix}-login-scale-out"
  autoscaling_group_name = aws_autoscaling_group.web.name
  adjustment_type        = "ChangeInCapacity"
  scaling_adjustment     = 1
  cooldown               = 300
  policy_type            = "SimpleScaling"
}

resource "aws_cloudwatch_metric_alarm" "active_logins" {
  count               = var.enable_login_scaling ? 1 : 0
  alarm_name          = "${var.name_prefix}-active-logins"
  namespace           = "Retrograde/Portal"
  metric_name         = "ActiveLogins"
  dimensions          = { AutoScalingGroupName = aws_autoscaling_group.web.name }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.scale_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_autoscaling_policy.login_scale_out[0].arn]
}
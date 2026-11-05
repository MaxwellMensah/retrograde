# Keep the existing aws_cloudwatch_log_group.app_logs (7-day retention).
resource "aws_iam_role_policy" "app_log_delivery" {
  name = "${var.name_prefix}-app-log-delivery"
  role = aws_iam_role.ec2_s3_reader.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.app_logs.arn}:*"
    }]
  })
}
output "monitoring_log_group" {
  value = aws_cloudwatch_log_group.app_logs.name
}
output "monitoring_alarm_name" {
  value = aws_cloudwatch_metric_alarm.alb_5xx.alarm_name
}

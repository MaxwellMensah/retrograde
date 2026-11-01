output "site_url" {
  description = "Open this in your browser (give it 3-5 minutes after apply for the first instance to finish booting)"
  value       = "http://${aws_lb.web.dns_name}"
}

output "run_the_test" {
  description = "Logs in 13 different students -> should trigger auto scaling"
  value       = "python simulate_logins.py --url http://${aws_lb.web.dns_name} --users 13"
}

output "just_under_the_trigger" {
  description = "12 users: nothing should happen"
  value       = "python simulate_logins.py --url http://${aws_lb.web.dns_name} --users 12 --logout"
}

output "asg_name" {
  value = aws_autoscaling_group.web.name
}

output "alarm_name" {
  value = aws_cloudwatch_metric_alarm.logins_high.alarm_name
}

output "app_bucket" {
  value = aws_s3_bucket.app.id
}

output "watch_instances" {
  description = "Instances in the group (re-run to see it grow after the test)"
  value       = "aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${var.asg_name} --query 'AutoScalingGroups[0].Instances[].[InstanceId,LifecycleState,HealthStatus]' --output table --region ${var.region}"
}

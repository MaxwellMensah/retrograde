output "app_url" {
  value       = var.domain_name != "" ? "https://${var.domain_name}" : "https://${aws_cloudfront_distribution.cdn.domain_name}"
  description = "Direct URL to access the application"
}

output "cloudfront_domain_name" {
  value       = aws_cloudfront_distribution.cdn.domain_name
  description = "CloudFront distribution default domain name"
}

output "alb_dns_name" {
  value       = aws_lb.web.dns_name
  description = "Application Load Balancer DNS name"
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.cdn.id
}
output "autoscaling_group_name" {
  value = aws_autoscaling_group.web.name
}
output "target_group_arn" {
  value = aws_lb_target_group.web.arn
}
output "assets_bucket_name" {
  value = aws_s3_bucket.static_assets.id
}

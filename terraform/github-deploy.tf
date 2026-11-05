variable "github_repository" {
  description = "GitHub owner/repository allowed to deploy"
  type        = string
  default     = "MaxwellMensah/retrograde"
}

variable "github_oidc_subject" {
  description = "Optional exact GitHub OIDC subject"
  type        = string
  default     = ""
}

# Lets GitHub Actions request temporary AWS credentials via OIDC.
resource "aws_iam_openid_connect_provider" "github_actions" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

resource "aws_iam_role" "github_deploy" {
  name = "${var.name_prefix}-github-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"

      Principal = {
        Federated = aws_iam_openid_connect_provider.github_actions.arn
      }

      Action = "sts:AssumeRoleWithWebIdentity"

      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = var.github_oidc_subject != "" ? var.github_oidc_subject : "repo:${var.github_repository}:ref:refs/heads/main"
        }
      }
    }]
  })
}

# Grants GitHub Actions permissions to upload assets to S3 and trigger ASG Instance Refreshes
resource "aws_iam_role_policy" "github_deploy_policy" {
  role = aws_iam_role.github_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:AbortMultipartUpload"
        ]
        Resource = [
          "${aws_s3_bucket.static_assets.arn}",
          "${aws_s3_bucket.static_assets.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "autoscaling:StartInstanceRefresh",
          "autoscaling:DescribeAutoScalingGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

output "github_deploy_role_arn" {
  value = aws_iam_role.github_deploy.arn
}

output "github_assets_bucket" {
  value = aws_s3_bucket.static_assets.id
}
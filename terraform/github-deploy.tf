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

# Lets GitHub Actions request temporary AWS credentials.
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

# Discovery APIs require wildcard resources. Rule edits are scoped to this stack's web SG.
resource "aws_iam_role_policy" "github_ssh_access" {
  role = aws_iam_role.github_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances", "ec2:DescribeSecurityGroups"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress"]
        Resource = aws_security_group.web.arn
      }
    ]
  })
}

# Allows EC2 to upload updated application files and assets.
resource "aws_iam_role_policy" "deployment_assets" {
  role = aws_iam_role.ec2_s3_reader.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:PutObject"]
      Resource = [
        "${aws_s3_bucket.static_assets.arn}/app/*",
        "${aws_s3_bucket.static_assets.arn}/static/*",
        "${aws_s3_bucket.static_assets.arn}/images/*"
      ]
    }]
  })
}

output "github_deploy_role_arn" {
  value = aws_iam_role.github_deploy.arn
}

output "github_ssh_security_group_id" {
  value = aws_security_group.web.id
}

output "github_assets_bucket" {
  value = aws_s3_bucket.static_assets.id
}

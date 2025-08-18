# IAM Role for Fluent Bit to send logs to CloudWatch
resource "aws_iam_role" "fluent_bit" {
  name = "fluent-bit-service-account-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:openemr:fluent-bit"
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-fluent-bit-role"
  }
}

resource "aws_iam_policy" "fluent_bit_cloudwatch" {
  name        = "${var.cluster_name}-fluent-bit-cloudwatch"
  description = "Policy for Fluent Bit to send logs to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          aws_cloudwatch_log_group.openemr_app.arn,
          aws_cloudwatch_log_group.openemr_access.arn,
          aws_cloudwatch_log_group.openemr_error.arn,
          aws_cloudwatch_log_group.openemr_audit.arn,
          "${aws_cloudwatch_log_group.openemr_app.arn}:*",
          "${aws_cloudwatch_log_group.openemr_access.arn}:*",
          "${aws_cloudwatch_log_group.openemr_error.arn}:*",
          "${aws_cloudwatch_log_group.openemr_audit.arn}:*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "fluent_bit_cloudwatch" {
  role       = aws_iam_role.fluent_bit.name
  policy_arn = aws_iam_policy.fluent_bit_cloudwatch.arn
}

# IAM Role for OpenEMR application
resource "aws_iam_role" "openemr" {
  name = "openemr-service-account-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:openemr:openemr-sa"
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-openemr-role"
  }
}

# IAM policy for OpenEMR to access AWS services
resource "aws_iam_policy" "openemr" {
  name        = "${var.cluster_name}-openemr-policy"
  description = "Policy for OpenEMR application to access AWS services"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "openemr" {
  role       = aws_iam_role.openemr.name
  policy_arn = aws_iam_policy.openemr.arn
}

# Note: EFS CSI Driver IAM role is now managed by the pod-identity module
# The old IRSA-based role has been removed as it's not needed with Pod Identity
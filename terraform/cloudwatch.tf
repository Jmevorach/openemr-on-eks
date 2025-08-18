# CloudWatch Log Groups for Application Logs
resource "aws_cloudwatch_log_group" "openemr_app" {
  name              = "/aws/eks/${var.cluster_name}/openemr/application"
  retention_in_days = var.app_logs_retention_days
  kms_key_id        = aws_kms_key.cloudwatch.arn

  tags = {
    Name        = "${var.cluster_name}-openemr-app-logs"
    Application = "OpenEMR"
    LogType     = "Application"
  }
}

resource "aws_cloudwatch_log_group" "openemr_access" {
  name              = "/aws/eks/${var.cluster_name}/openemr/access"
  retention_in_days = var.app_logs_retention_days
  kms_key_id        = aws_kms_key.cloudwatch.arn

  tags = {
    Name        = "${var.cluster_name}-openemr-access-logs"
    Application = "OpenEMR"
    LogType     = "Access"
  }
}

resource "aws_cloudwatch_log_group" "openemr_error" {
  name              = "/aws/eks/${var.cluster_name}/openemr/error"
  retention_in_days = var.app_logs_retention_days
  kms_key_id        = aws_kms_key.cloudwatch.arn

  tags = {
    Name        = "${var.cluster_name}-openemr-error-logs"
    Application = "OpenEMR"
    LogType     = "Error"
  }
}

resource "aws_cloudwatch_log_group" "openemr_audit" {
  name              = "/aws/eks/${var.cluster_name}/openemr/audit"
  retention_in_days = var.audit_logs_retention_days
  kms_key_id        = aws_kms_key.cloudwatch.arn

  tags = {
    Name        = "${var.cluster_name}-openemr-audit-logs"
    Application = "OpenEMR"
    LogType     = "Audit"
  }
}
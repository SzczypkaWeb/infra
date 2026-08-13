resource "aws_ssm_parameter" "database_url" {
  name  = "/szczypka-web/backend/database-url"
  type  = "SecureString"
  value = "managed-outside-terraform"

  lifecycle {
    ignore_changes = [value]
  }
}
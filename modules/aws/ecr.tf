resource "aws_ecr_repository" "backend" {
  name = "szczypka-web-backend"
  force_delete = true
}
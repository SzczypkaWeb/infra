resource "aws_db_instance" "main" {
  identifier     = "szczypka-web-db"
  engine         = "postgres"
  engine_version = "18.3"
  instance_class = "db.t4g.micro"

  allocated_storage     = 20
  max_allocated_storage = 1000
  storage_type          = "gp2"
  storage_encrypted     = true

  db_name  = "szczypkaweb"
  username = "kertoip"
  manage_master_user_password = true

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = "default-vpc-01cd2de7acd11ec1d"
  parameter_group_name   = "default.postgres18"

  publicly_accessible = true
  multi_az             = false
  network_type         = "IPV4"

  backup_retention_period = 1
  backup_window           = "03:01-03:31"
  maintenance_window      = "mon:00:35-mon:01:05"

  auto_minor_version_upgrade = true
  deletion_protection        = false
  copy_tags_to_snapshot      = true

  performance_insights_enabled          = true
  performance_insights_kms_key_id        = "arn:aws:kms:eu-central-1:637423368410:key/2f95e73f-304b-4731-b3f5-d89206642139"
  performance_insights_retention_period  = 7

  license_model    = "postgresql-license"
  ca_cert_identifier = "rds-ca-rsa2048-g1"

  apply_immediately    = false
  skip_final_snapshot  = true
}
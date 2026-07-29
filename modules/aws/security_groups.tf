resource "aws_security_group" "backend" {
  name        = "szczypka-web-backend-sg"
  description = "Allow inbound 3000 for backend"
  vpc_id      = "vpc-01cd2de7acd11ec1d"

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds" {
  name        = "szczypka-web-db-sg"
  description = "Created by RDS management console"
  vpc_id      = "vpc-01cd2de7acd11ec1d"

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    cidr_blocks     = ["217.96.176.208/32"]
    security_groups = [aws_security_group.backend.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
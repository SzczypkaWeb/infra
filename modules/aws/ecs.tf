resource "aws_ecs_cluster" "main" {
  name = "szczypka-web-cluster"
}

resource "aws_ecs_task_definition" "backend" {
  family                   = "szczypka-web-backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name  = "backend"
      image = "${aws_ecr_repository.backend.repository_url}:latest"
      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]
      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = aws_ssm_parameter.database_url.arn
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.backend.name
          "awslogs-region"        = "eu-central-1"
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

resource "aws_ecs_service" "backend" {
  name              = "szczypka-web-backend-service"
  cluster           = aws_ecs_cluster.main.id
  task_definition   = "${aws_ecs_task_definition.backend.family}:${aws_ecs_task_definition.backend.revision}"
  desired_count     = 1
  launch_type       = "FARGATE"
  platform_version  = "LATEST"

  availability_zone_rebalancing = "ENABLED"
  wait_for_steady_state          = false

  network_configuration {
    subnets          = ["subnet-086627364cc90d89d"]
    security_groups  = [aws_security_group.backend.id]
    assign_public_ip = true
  }
}
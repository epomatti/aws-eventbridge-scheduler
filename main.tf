terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.7.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "aws_db_instance" "default" {
  identifier     = "database-1"
  db_name        = "testdb"
  engine         = "postgres"
  engine_version = "15.3"
  username       = "dbadmin"
  password       = "DF1238DCVc#R53"

  publicly_accessible = false
  instance_class      = "db.t4g.micro"
  allocated_storage   = "30"
  storage_type        = "gp3"
  storage_encrypted   = false
  multi_az            = false

  # Upgrades
  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false
  apply_immediately           = false
  maintenance_window          = "Sun:05:00-Sun:06:00"

  deletion_protection      = false
  skip_final_snapshot      = true
  delete_automated_backups = true

  # Backup
  backup_retention_period = 14
  backup_window           = "08:00-09:00"
  copy_tags_to_snapshot   = true
}

resource "aws_iam_role" "eventbridge" {
  name = "CustomEventBridgeSchedulerForRDS"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
        "Action" : "sts:AssumeRole"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rds" {
  role       = aws_iam_role.eventbridge.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSFullAccess"
}

resource "aws_iam_role_policy_attachment" "eventbridge_scheduler" {
  role       = aws_iam_role.eventbridge.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEventBridgeSchedulerFullAccess"
}


# https://docs.aws.amazon.com/scheduler/latest/UserGuide/managing-targets-universal.html

resource "aws_scheduler_schedule" "rds_stop" {
  name  = "StopDBInstance"
  state = "ENABLED"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(${var.stop_cron})"
  schedule_expression_timezone = var.timezone

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:rds:stopDBInstance"
    role_arn = aws_iam_role.eventbridge.arn

    input = jsonencode({
      DbInstanceIdentifier = "${aws_db_instance.default.identifier}"
    })

    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 3
    }
  }
}

resource "aws_scheduler_schedule" "rds_start" {
  name  = "StartDBInstance"
  state = "ENABLED"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(${var.start_cron})"
  schedule_expression_timezone = var.timezone

  target {
    arn      = "arn:aws:scheduler:::aws-sdk:rds:startDBInstance"
    role_arn = aws_iam_role.eventbridge.arn

    input = jsonencode({
      DbInstanceIdentifier = "${aws_db_instance.default.identifier}"
    })

    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 3
    }
  }
}

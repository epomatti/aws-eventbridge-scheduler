terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.33.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

locals {
  aws_account_id = data.aws_caller_identity.current.account_id
  db_name        = "testdb"
}

resource "aws_db_instance" "default" {
  identifier     = "database-1"
  db_name        = local.db_name
  engine         = "postgres"
  engine_version = "16.1"
  username       = "dbadmin"
  password       = "DF1238DCVc#R53"

  publicly_accessible = false
  instance_class      = "db.t4g.medium"
  allocated_storage   = "30"
  storage_type        = "gp3"
  storage_encrypted   = false
  multi_az            = false

  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false
  apply_immediately           = false

  deletion_protection      = false
  skip_final_snapshot      = true
  delete_automated_backups = true

  performance_insights_enabled          = true
  performance_insights_retention_period = 7 # Free
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.emaccess.arn
  enabled_cloudwatch_logs_exports       = ["postgresql", "upgrade"]

  depends_on = [aws_iam_role_policy_attachment.AmazonRDSEnhancedMonitoringRole]
}

# Enhanced Monitoring
resource "aws_iam_role" "emaccess" {
  name = "emaccess"

  # Implements protection for the confused deputy problem
  # https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_Monitoring.OS.Enabling.html#USER_Monitoring.OS.confused-deputy
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "monitoring.rds.amazonaws.com"
        },
        "Action" : "sts:AssumeRole",
        "Condition" : {
          "StringLike" : {
            "aws:SourceArn" : "arn:aws:rds:${var.aws_region}:${local.aws_account_id}:db:${local.db_name}"
          },
          "StringEquals" : {
            "aws:SourceAccount" : "${local.aws_account_id}"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "AmazonRDSEnhancedMonitoringRole" {
  role       = aws_iam_role.emaccess.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}


### EventBridge ###
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

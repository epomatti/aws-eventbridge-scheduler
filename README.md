# AWS EventBridge Scheduler

Stopping and starting an RDS instance on schedule using Event Bridge scheduler.

Create the `.auto.tfars` file. Edit as needed.

```terraform
aws_region = "sa-east-1"
stop_cron  = "0 23 ? * * *"
start_cron = "20 23 ? * * *"
timezone   = "America/Sao_Paulo"
```

This recipe requires a default VPC to create the RDS instance.

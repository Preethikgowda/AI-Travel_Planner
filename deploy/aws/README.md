# AWS Deployment Guide

This repo now uses a 3-tier monolith shape:

- Presentation tier: React frontend on S3 + CloudFront
- Application tier: one FastAPI backend container on ECS Fargate
- Data tier: one Amazon RDS PostgreSQL database

Only the backend is exposed through an Application Load Balancer. RDS should remain private.

## 1. Generate Production Secrets

From the repo root:

```powershell
.\scripts\generate-production-secrets.ps1
```

Store the generated values in AWS Secrets Manager.

## 2. Create RDS

Create one PostgreSQL RDS instance and one database:

```text
ai_travel
```

Create a database URL:

```text
postgresql+psycopg://ai_travel:<password>@<rds-endpoint>:5432/ai_travel
```

Save it in Secrets Manager as the backend `DATABASE_URL`.

## 3. Build and Push Backend Image

Install and configure AWS CLI, then run:

```powershell
.\scripts\build-and-push-ecr.ps1 -AwsAccountId "<account-id>" -AwsRegion "us-east-1"
```

This builds and pushes one image:

```text
ai-travel-backend
```

## 4. Register ECS Task Definition

Open:

```text
deploy/aws/task-definitions/backend.json
```

Replace:

```text
<account-id>
<region>
<ecs-task-execution-role-arn>
<ecs-task-role-arn>
<secrets-manager-...-arn>
https://app.example.com
```

Then register it:

```powershell
aws ecs register-task-definition --cli-input-json file://deploy/aws/task-definitions/backend.json
```

## 5. Create ECS Backend Service

Create one Fargate service:

```text
ai-travel-backend
```

Attach it to a public Application Load Balancer target group on container port `8000`.

## 6. Build and Upload Frontend

Create an S3 bucket for the frontend and put CloudFront in front of it. Then build with the real API URL:

```powershell
.\scripts\deploy-frontend-s3.ps1 `
  -BucketName "<frontend-bucket-name>" `
  -ApiBaseUrl "https://api.example.com/api" `
  -CloudFrontDistributionId "<distribution-id>"
```

For React Router browser routing, configure CloudFront custom error responses:

```text
403 -> /index.html -> 200
404 -> /index.html -> 200
```

## 7. DNS and TLS

Recommended DNS:

```text
app.example.com -> CloudFront
api.example.com -> Application Load Balancer
```

Use ACM certificates for both hostnames. CloudFront certificates must be in `us-east-1`.

## 8. Final Checks

Check:

```text
https://api.example.com/health
https://app.example.com
```

Then test registration, login, trip creation, trip history, AI assistant, weather, hotels, and places.

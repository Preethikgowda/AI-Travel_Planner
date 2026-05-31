# AWS Deployment Guide

This repo is prepared for this AWS shape:

- React frontend: S3 + CloudFront
- Backend containers: ECS Fargate
- Public API entrypoint: Application Load Balancer -> `api-gateway`
- Internal services: ECS Service Connect or AWS Cloud Map
- Databases: Amazon RDS PostgreSQL
- Secrets: AWS Secrets Manager

Only `api-gateway` should be public. `user-service`, `travel-service`, `ai-service`, `utility-service`, and RDS should run in private networking.

## 1. Generate Production Secrets

From the repo root:

```powershell
.\scripts\generate-production-secrets.ps1
```

Store the generated values in AWS Secrets Manager. Use the same `JWT_SECRET_KEY` for `user-service`, `travel-service`, `ai-service`, and `utility-service`.

## 2. Create RDS

Create PostgreSQL on RDS and create two databases:

```text
user_db
travel_db
```

Create service users or use one managed username with two database URLs:

```text
postgresql+psycopg://user_service:<password>@<rds-endpoint>:5432/user_db
postgresql+psycopg://travel_service:<password>@<rds-endpoint>:5432/travel_db
```

Save both URLs as Secrets Manager secrets.

## 3. Build and Push Backend Images

Install and configure AWS CLI, then run:

```powershell
.\scripts\build-and-push-ecr.ps1 -AwsAccountId "<account-id>" -AwsRegion "us-east-1"
```

This builds and pushes:

```text
ai-travel-api-gateway
ai-travel-user-service
ai-travel-travel-service
ai-travel-ai-service
ai-travel-utility-service
```

## 4. Register ECS Task Definitions

Use the JSON templates in `deploy/aws/task-definitions`.

Before registering them, replace:

```text
<account-id>
<region>
<ecs-task-execution-role-arn>
<ecs-task-role-arn>
<secrets-manager-...-arn>
https://app.example.com
```

Then register each task definition:

```powershell
aws ecs register-task-definition --cli-input-json file://deploy/aws/task-definitions/user-service.json
aws ecs register-task-definition --cli-input-json file://deploy/aws/task-definitions/travel-service.json
aws ecs register-task-definition --cli-input-json file://deploy/aws/task-definitions/ai-service.json
aws ecs register-task-definition --cli-input-json file://deploy/aws/task-definitions/utility-service.json
aws ecs register-task-definition --cli-input-json file://deploy/aws/task-definitions/api-gateway.json
```

## 5. Create ECS Services

Create services in this order:

1. `user-service`
2. `travel-service`
3. `ai-service`
4. `utility-service`
5. `api-gateway`

Use ECS Service Connect or Cloud Map names matching the gateway template:

```text
user-service.ai-travel.local
travel-service.ai-travel.local
ai-service.ai-travel.local
utility-service.ai-travel.local
```

Attach only `api-gateway` to a public Application Load Balancer target group. The other services should be internal only.

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

## Production Guards Added

When `ENVIRONMENT=production`, backend services now reject unsafe settings:

- placeholder or short `JWT_SECRET_KEY`
- localhost database URLs
- localhost CORS origins
- localhost upstream service URLs in the API gateway

This prevents accidental deployment with local development settings.

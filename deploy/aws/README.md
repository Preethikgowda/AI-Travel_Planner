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

## 3. Create Document S3 Bucket and KMS Key

Create one private bucket per environment:

```text
ai-travel-planner-prod-documents
```

Enable:

```text
Block Public Access
Bucket Versioning
Default encryption: SSE-KMS
CloudTrail data events for object-level audit
Lifecycle cleanup for incomplete multipart uploads and deleted object versions
```

Create a customer-managed KMS key:

```text
alias/ai-travel-planner-prod-s3-documents
```

Store the KMS key ARN in Secrets Manager as `S3_DOCUMENT_KMS_KEY_ID`.

Recommended S3 CORS for browser direct uploads:

```json
[
  {
    "AllowedOrigins": ["https://app.example.com"],
    "AllowedMethods": ["PUT", "GET"],
    "AllowedHeaders": [
      "Content-Type",
      "x-amz-server-side-encryption",
      "x-amz-server-side-encryption-aws-kms-key-id",
      "x-amz-meta-*"
    ],
    "ExposeHeaders": ["ETag"],
    "MaxAgeSeconds": 3000
  }
]
```

Attach this bucket policy. Replace placeholders before applying:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::ai-travel-planner-prod-documents",
        "arn:aws:s3:::ai-travel-planner-prod-documents/*"
      ],
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    },
    {
      "Sid": "DenyUnencryptedObjectUploads",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::ai-travel-planner-prod-documents/*",
      "Condition": {
        "StringNotEquals": {
          "s3:x-amz-server-side-encryption": "aws:kms"
        }
      }
    },
    {
      "Sid": "DenyWrongKmsKey",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::ai-travel-planner-prod-documents/*",
      "Condition": {
        "StringNotEquals": {
          "s3:x-amz-server-side-encryption-aws-kms-key-id": "<kms-key-arn>"
        }
      }
    }
  ]
}
```

The ECS task role needs:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::ai-travel-planner-prod-documents/users/*"
    },
    {
      "Effect": "Allow",
      "Action": ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"],
      "Resource": "<kms-key-arn>"
    }
  ]
}
```

For malware scanning, add an S3 event to a scanner Lambda or managed scanning service and keep new uploads quarantined until scan status is clean. The current application verifies object existence, size, and KMS encryption; scanning is the next production hardening step.

## 4. Build and Push Backend Image

Install and configure AWS CLI, then run:

```powershell
.\scripts\build-and-push-ecr.ps1 -AwsAccountId "<account-id>" -AwsRegion "us-east-1"
```

This builds and pushes one image:

```text
ai-travel-backend
```

## 5. Register ECS Task Definition

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
<secrets-manager-s3-document-kms-key-id-arn>
https://app.example.com
```

Then register it:

```powershell
aws ecs register-task-definition --cli-input-json file://deploy/aws/task-definitions/backend.json
```

## 6. Create ECS Backend Service

Create one Fargate service:

```text
ai-travel-backend
```

Attach it to a public Application Load Balancer target group on container port `8000`.

## 7. Build and Upload Frontend

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

## 8. DNS and TLS

Recommended DNS:

```text
app.example.com -> CloudFront
api.example.com -> Application Load Balancer
```

Use ACM certificates for both hostnames. CloudFront certificates must be in `us-east-1`.

## 9. Final Checks

Check:

```text
https://api.example.com/health
https://app.example.com
```

Then test registration, login, trip creation, trip history, document upload/download/delete, AI assistant attachment upload, weather, hotels, and places.

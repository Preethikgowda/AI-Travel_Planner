<#
PowerShell helper to bootstrap Terraform remote state and deploy the entire infrastructure.
Usage:
  1. Configure AWS credentials in environment or profile.
  2. Edit terraform/terraform.tfvars.example -> copy to terraform/terraform.tfvars and set values.
  3. Run this script from repository root in PowerShell:
     ./terraform/deploy.ps1 -env prod
#>
param(
  [string]$env = "prod"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$terraformDir = "terraform"
$bootstrapDir = Join-Path $terraformDir "bootstrap"
$envFile = Join-Path $terraformDir "environments/$env/terraform.tfvars"
$secretsFile = Join-Path $terraformDir "terraform.tfvars"

if (-not (Test-Path $envFile)) {
  Write-Error "Environment tfvars not found: $envFile"
  exit 1
}

if (-not (Test-Path $secretsFile)) {
  Write-Warning "Secrets file (terraform.tfvars) not found. Checking if it's strictly needed..."
}

Write-Host "Bootstrapping remote state (S3 + DynamoDB)..."
Push-Location $bootstrapDir
terraform init
terraform apply -auto-approve -var-file="../environments/$env/terraform.tfvars"
if ($LASTEXITCODE -ne 0) {
  Write-Error "Bootstrap terraform apply failed"
  exit 1
}

Write-Host "Fetching bootstrap outputs..."
$outputs = terraform output -json | ConvertFrom-Json
$bucket = $outputs.tfstate_bucket.value
$table = $outputs.lock_table.value
Pop-Location

if (-not $bucket -or -not $table) {
  Write-Error "Bootstrap failed to produce backend bucket/table"
  exit 1
}

$backendFile = Join-Path $terraformDir "backend.tf"
$backendContent = @"
terraform {
  backend "s3" {
    bucket         = "$bucket"
    key            = "$env/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    dynamodb_table = "$table"
  }
}
"@

Set-Content -Path $backendFile -Value $backendContent -Force
Write-Host "Wrote backend configuration to $backendFile"

# Initialize and apply main terraform
Push-Location $terraformDir
terraform init -reconfigure

# Select or create workspace
$workspaceExists = (terraform workspace list) -match "\b$env\b"
if ($workspaceExists) {
  terraform workspace select $env
} else {
  terraform workspace new $env
}

Write-Host "Planning deployment for environment: $env"
$planCmd = "terraform plan -var-file=`"environments/$env/terraform.tfvars`""
if (Test-Path "terraform.tfvars") {
    $planCmd += " -var-file=`"terraform.tfvars`""
}
$planCmd += " -out=tfplan"
Invoke-Expression $planCmd

Write-Host "Auto-approving deployment based on user confirmation..."

terraform apply -auto-approve tfplan
Pop-Location

Write-Host "Deployment complete. Check Terraform outputs for resource names."

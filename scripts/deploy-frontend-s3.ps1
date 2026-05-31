param(
  [Parameter(Mandatory = $true)]
  [string]$BucketName,

  [Parameter(Mandatory = $true)]
  [string]$ApiBaseUrl,

  [string]$CloudFrontDistributionId = ""
)

$ErrorActionPreference = "Stop"

function Invoke-Checked {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,

    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  & $FilePath @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "$FilePath failed with exit code $LASTEXITCODE"
  }
}

Push-Location frontend
try {
  $env:VITE_API_BASE_URL = $ApiBaseUrl
  Invoke-Checked "npm" @("ci")
  Invoke-Checked "npm" @("run", "build")
}
finally {
  Pop-Location
}

Invoke-Checked "aws" @("s3", "sync", "frontend/dist", "s3://$BucketName", "--delete")

if ($CloudFrontDistributionId) {
  Invoke-Checked "aws" @("cloudfront", "create-invalidation", "--distribution-id", $CloudFrontDistributionId, "--paths", "/*")
}

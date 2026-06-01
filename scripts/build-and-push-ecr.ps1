param(
  [Parameter(Mandatory = $true)]
  [string]$AwsAccountId,

  [string]$AwsRegion = "us-east-1",

  [string]$RepositoryName = "ai-travel-backend"
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

$registry = "$AwsAccountId.dkr.ecr.$AwsRegion.amazonaws.com"
$localTag = "$RepositoryName`:latest"
$remoteTag = "$registry/$RepositoryName`:latest"

$password = aws ecr get-login-password --region $AwsRegion
if ($LASTEXITCODE -ne 0) {
  throw "aws ecr get-login-password failed with exit code $LASTEXITCODE"
}
$password | docker login --username AWS --password-stdin $registry
if ($LASTEXITCODE -ne 0) {
  throw "docker login failed with exit code $LASTEXITCODE"
}

aws ecr describe-repositories --repository-names $RepositoryName --region $AwsRegion 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
  Invoke-Checked "aws" @("ecr", "create-repository", "--repository-name", $RepositoryName, "--region", $AwsRegion)
}

Invoke-Checked "docker" @("build", "-t", $localTag, "backend")
Invoke-Checked "docker" @("tag", $localTag, $remoteTag)
Invoke-Checked "docker" @("push", $remoteTag)

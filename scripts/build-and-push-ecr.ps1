param(
  [Parameter(Mandatory = $true)]
  [string]$AwsAccountId,

  [string]$AwsRegion = "us-east-1",

  [string]$RepositoryPrefix = "ai-travel"
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

$services = @(
  @{ Name = "api-gateway"; Context = "services/api-gateway"; Repository = "$RepositoryPrefix-api-gateway" },
  @{ Name = "user-service"; Context = "services/user-service"; Repository = "$RepositoryPrefix-user-service" },
  @{ Name = "travel-service"; Context = "services/travel-service"; Repository = "$RepositoryPrefix-travel-service" },
  @{ Name = "ai-service"; Context = "services/ai-service"; Repository = "$RepositoryPrefix-ai-service" },
  @{ Name = "utility-service"; Context = "services/utility-service"; Repository = "$RepositoryPrefix-utility-service" }
)

$registry = "$AwsAccountId.dkr.ecr.$AwsRegion.amazonaws.com"

$password = aws ecr get-login-password --region $AwsRegion
if ($LASTEXITCODE -ne 0) {
  throw "aws ecr get-login-password failed with exit code $LASTEXITCODE"
}
$password | docker login --username AWS --password-stdin $registry
if ($LASTEXITCODE -ne 0) {
  throw "docker login failed with exit code $LASTEXITCODE"
}

foreach ($service in $services) {
  $repository = $service.Repository
  $localTag = "$repository`:latest"
  $remoteTag = "$registry/$repository`:latest"

  aws ecr describe-repositories --repository-names $repository --region $AwsRegion 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Invoke-Checked "aws" @("ecr", "create-repository", "--repository-name", $repository, "--region", $AwsRegion)
  }

  Invoke-Checked "docker" @("build", "-t", $localTag, $service.Context)
  Invoke-Checked "docker" @("tag", $localTag, $remoteTag)
  Invoke-Checked "docker" @("push", $remoteTag)
}

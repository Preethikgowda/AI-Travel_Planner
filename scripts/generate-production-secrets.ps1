$ErrorActionPreference = "Stop"

function New-Secret {
  param([int]$Bytes = 48)

  $buffer = New-Object byte[] $Bytes
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try {
    $rng.GetBytes($buffer)
  }
  finally {
    $rng.Dispose()
  }
  [Convert]::ToBase64String($buffer)
}

Write-Output "JWT_SECRET_KEY=$(New-Secret -Bytes 64)"
Write-Output "USER_DB_PASSWORD=$(New-Secret -Bytes 32)"
Write-Output "TRAVEL_DB_PASSWORD=$(New-Secret -Bytes 32)"

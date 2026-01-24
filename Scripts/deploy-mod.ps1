param(
  [Parameter(Mandatory = $true)]
  [string]$ModName,

  [string]$RepoModsRoot = "$PSScriptRoot\..\Mods",
  [string]$WorkshopRoot = "$env:USERPROFILE\Zomboid\workshop",

  [bool]$Clean = $false
)

$ErrorActionPreference = "Stop"

$source = Join-Path $RepoModsRoot $ModName
$dest   = Join-Path $WorkshopRoot $ModName

Write-Host "Deploying mod '$ModName'"
Write-Host "  From: $source"
Write-Host "  To:   $dest"

if (-not (Test-Path $source)) {
  throw "Source mod folder not found: $source"
}

if ($Clean -and (Test-Path $dest)) {
  Write-Host "Cleaning destination..."
  Remove-Item -Recurse -Force $dest
}

New-Item -ItemType Directory -Path $dest -Force | Out-Null

$null = robocopy $source $dest /MIR /R:2 /W:1 /NFL /NDL /NJH /NJS

if ($LASTEXITCODE -ge 8) {
  throw "Robocopy failed with exit code $LASTEXITCODE"
}

Write-Host "Deploy complete."

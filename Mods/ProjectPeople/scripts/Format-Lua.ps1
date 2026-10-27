#requires -Version 7.2
# StyLua 2.6.0 or later. Only formats runtime Lua, never tests or saved evidence.
[CmdletBinding()]
param(
    [switch]$Check,
    [string]$StyLua = 'stylua'
)

$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$formatArgs = @('--config-path', (Join-Path $projectRoot '.stylua.toml'), '--verify')
if ($Check) { $formatArgs += '--check' }
$formatArgs += Join-Path $projectRoot '42/media/lua'
& $StyLua @formatArgs
if ($LASTEXITCODE -ne 0) { throw "Lua formatting failed (exit $LASTEXITCODE)." }

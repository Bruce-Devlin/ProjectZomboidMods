#requires -Version 7.2
<#
.SYNOPSIS
Builds and verifies an unpublished Project People development snapshot.
.DESCRIPTION
Copies only whitelisted Build 42/common runtime paths into a unique directory
under this workspace's .pztools/packages. Creates a Workshop-layout folder,
SHA-256 manifest and ZIP, then independently verifies ZIP entries and hashes.
Existing artifacts are never deleted or overwritten. This is not an alpha gate.
PowerShell 7 is required for long paths in this nested workspace.
#>
[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')]
    [string]$Version = '0.0.0-dev',

    [ValidateLength(1, 1000)]
    [string]$DeveloperStatus = 'Stage 0 engine investigation is incomplete. This is a local development snapshot, not a playable alpha. Engine gates and the connected gameplay loop remain unverified.'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$workspaceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..')).TrimEnd('\', '/')
$workspacePrefix = $workspaceRoot + [System.IO.Path]::DirectorySeparatorChar
$utf8 = New-Object System.Text.UTF8Encoding($false)
$modId = 'ProjectPeople'
$artifactRoot = $null
$completed = $false

function Assert-WorkspacePath([string]$Path) {
    $full = [System.IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($workspacePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside the Project People workspace: $full"
    }
    return $full
}

function Assert-NoReparsePoint([string]$Path) {
    $full = Assert-WorkspacePath $Path
    $relative = $full.Substring($workspacePrefix.Length)
    $current = $workspaceRoot
    foreach ($part in $relative.Split([char[]]'\/')) {
        if ([string]::IsNullOrEmpty($part)) { continue }
        $current = Join-Path $current $part
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Packaging does not follow symbolic links or junctions: $current"
            }
        }
    }
}

function New-ContainedDirectory([string]$Path) {
    $full = Assert-WorkspacePath $Path
    Assert-NoReparsePoint $full
    [System.IO.Directory]::CreateDirectory($full) | Out-Null
    return $full
}

function Get-RelativePackagePath([string]$Root, [string]$Path) {
    $prefix = $Root.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    $full = [System.IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "File is outside its expected root: $full"
    }
    return $full.Substring($prefix.Length).Replace('\', '/')
}

function Write-Utf8File([string]$Path, [string]$Text) {
    $full = Assert-WorkspacePath $Path
    Assert-NoReparsePoint $full
    if (Test-Path -LiteralPath $full) { throw "Refusing to overwrite artifact: $full" }
    [System.IO.File]::WriteAllText($full, $Text, $utf8)
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-StreamSha256([System.IO.Stream]$Stream) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [System.BitConverter]::ToString($sha.ComputeHash($Stream)).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-SafeFiles([string]$Root) {
    Assert-NoReparsePoint $Root
    $pending = New-Object 'System.Collections.Generic.Stack[string]'
    $pending.Push($Root)
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        foreach ($entry in Get-ChildItem -LiteralPath $directory -Force) {
            if (($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Packaging does not follow symbolic links or junctions: $($entry.FullName)"
            }
            if ($entry.PSIsContainer) { $pending.Push($entry.FullName) }
            else { Write-Output $entry }
        }
    }
}

# Runtime paths and extensions are both allowlisted. Unknown content is recorded
# as excluded rather than recursively copying a project or test deployment.
$mediaDirectories = @(
    'lua', 'scripts', 'animsets', 'anims_x', 'actiongroups', 'models_x',
    'textures', 'texturepacks', 'sound', 'maps', 'ui', 'clothing', 'fonts'
)
$runtimeExtensions = @(
    '.lua', '.txt', '.xml', '.png', '.jpg', '.jpeg', '.dds', '.ogg', '.wav',
    '.fbx', '.x', '.mesh', '.anim', '.pack', '.tmx', '.tsx', '.lotheader',
    '.lotpack', '.bin', '.tiles', '.ttf', '.otf'
)
$blockedSegments = @(
    '.agents', '.pztests', '.pztools', '.git', '.github', '.vscode', '.idea',
    'node_modules', '__pycache__', 'tools', 'tooling', 'engine-reference',
    'reference', 'references', 'research', 'tests'
)

function Test-RuntimePath([string]$Relative) {
    $parts = $Relative.ToLowerInvariant().Split('/')
    if ($parts.Count -lt 2 -or $parts[0] -notin @('42', 'common')) { return $false }
    foreach ($part in $parts) {
        if ($part -in $blockedSegments -or $part.StartsWith('.')) { return $false }
    }
    if ($parts.Count -eq 2) {
        return $Relative.ToLowerInvariant() -eq '42/mod.info' -or
            $parts[1] -in @('poster.png', 'icon.png', 'preview.png')
    }
    if ($parts[1] -ne 'media') { return $false }
    if ($parts.Count -eq 3) { return $parts[2] -in @('fileguidtable.xml', 'sandbox-options.txt') }
    if ($parts[2] -notin $mediaDirectories) { return $false }
    if ([System.IO.Path]::GetExtension($Relative).ToLowerInvariant() -eq '.json') {
        return $Relative -match '^(42|common)/media/lua/shared/Translate/[^/]+/[A-Za-z_]+\.json$'
    }
    return [System.IO.Path]::GetExtension($Relative).ToLowerInvariant() -in $runtimeExtensions
}

try {
    if (((Get-Item -LiteralPath $workspaceRoot -Force).Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'The workspace root must not be a symbolic link or junction.'
    }
    $metadataPath = Assert-WorkspacePath (Join-Path $workspaceRoot '42/mod.info')
    Assert-NoReparsePoint $metadataPath
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) { throw '42/mod.info is required.' }
    $metadata = @{}
    foreach ($line in Get-Content -LiteralPath $metadataPath) {
        if ($line -match '^\s*([^#=]+?)\s*=(.*)$') { $metadata[$matches[1].Trim()] = $matches[2].Trim() }
    }
    if ($metadata['id'] -ne $modId) { throw "Expected mod ID $modId in 42/mod.info." }
    if ($metadata.ContainsKey('require') -and -not [string]::IsNullOrWhiteSpace($metadata['require'])) {
        throw 'The self-contained development package cannot declare required external mods.'
    }
    $title = if ($metadata.ContainsKey('name') -and $metadata['name']) { $metadata['name'] } else { 'Project People' }
    $statusLine = ($DeveloperStatus -replace '[\r\n]+', ' ').Trim()
    if ([string]::IsNullOrWhiteSpace($statusLine)) { throw 'DeveloperStatus must contain text.' }

    $generated = [DateTime]::UtcNow
    $uniqueName = '{0}-{1}-{2}-{3}' -f $modId, $Version, $generated.ToString('yyyyMMddTHHmmssfffZ'), [Guid]::NewGuid().ToString('N').Substring(0, 12)
    $packagesRoot = New-ContainedDirectory (Join-Path $workspaceRoot '.pztools/packages')
    $artifactRoot = Assert-WorkspacePath (Join-Path $packagesRoot $uniqueName)
    if (Test-Path -LiteralPath $artifactRoot) { throw "Artifact already exists: $artifactRoot" }
    $artifactRoot = New-ContainedDirectory $artifactRoot
    $packageRoot = New-ContainedDirectory (Join-Path $artifactRoot 'package')
    $payloadRoot = New-ContainedDirectory (Join-Path $packageRoot ('Contents/mods/' + $modId))
    New-ContainedDirectory (Join-Path $payloadRoot 'common') | Out-Null

    $runtimeFiles = New-Object 'System.Collections.Generic.List[object]'
    $excluded = New-Object 'System.Collections.Generic.List[string]'
    foreach ($tree in @('42', 'common')) {
        $sourceRoot = Assert-WorkspacePath (Join-Path $workspaceRoot $tree)
        if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
            if ($tree -eq '42') { throw 'Build 42 runtime directory is required.' }
            continue
        }
        foreach ($source in @(Get-SafeFiles $sourceRoot | Sort-Object FullName)) {
            $relative = Get-RelativePackagePath $workspaceRoot $source.FullName
            if (-not (Test-RuntimePath $relative)) { $excluded.Add($relative); continue }
            $destination = Assert-WorkspacePath (Join-Path $payloadRoot $relative)
            New-ContainedDirectory (Split-Path -Parent $destination) | Out-Null
            $before = Get-Sha256 $source.FullName
            [System.IO.File]::Copy($source.FullName, $destination, $false)
            $copied = Get-Sha256 $destination
            if ($before -ne $copied -or (Get-Sha256 $source.FullName) -ne $copied) {
                throw "Source changed while packaging; regenerate after edits finish: $relative"
            }
            $runtimeFiles.Add([ordered]@{
                Source = $relative
                Path = Get-RelativePackagePath $packageRoot $destination
                Bytes = (Get-Item -LiteralPath $destination).Length
                SHA256 = $copied
            })
        }
    }

    $readme = @"
$title | LOCAL DEVELOPMENT SNAPSHOT
Version: $Version

NOT A PLAYABLE ALPHA. NOT PUBLISHED.
$statusLine

This folder uses the intended Workshop layout:
Contents/mods/$modId/42/mod.info
Contents/mods/$modId/common/

The contents are incomplete development work. Package verification proves file
boundaries and SHA-256 integrity only; it does not prove installation, gameplay,
multiplayer, background protection, succession or a passed engine gate.

For an authorized isolated local test, the mod folder is Contents/mods/$modId.
Use disposable test data. This script does not install, deploy or publish it.
Workshop publication metadata/artwork and release acceptance remain separate.

manifest.json lists every archived file except itself. The sibling
verification.json also records the manifest and archive hashes and ZIP checks.
Development references, test harnesses, Build 41 and tooling are excluded.
"@
    Write-Utf8File (Join-Path $packageRoot 'README-DEVELOPMENT.txt') ($readme + "`n")
    $workshop = @(
        'version=1',
        ('title=' + $title + ' | Local development'),
        ('description=Unpublished development snapshot ' + $Version + '. Not a playable alpha. ' + $statusLine),
        'tags=Build 42',
        'visibility=private'
    ) -join "`n"
    Write-Utf8File (Join-Path $packageRoot 'workshop.txt') ($workshop + "`n")

    $allFiles = New-Object 'System.Collections.Generic.List[object]'
    foreach ($file in @(Get-SafeFiles $packageRoot | Sort-Object FullName)) {
        $allFiles.Add([ordered]@{
            Path = Get-RelativePackagePath $packageRoot $file.FullName
            Bytes = $file.Length
            SHA256 = Get-Sha256 $file.FullName
        })
    }
    $manifest = [ordered]@{
        SchemaVersion = 1
        ModId = $modId
        Version = $Version
        GeneratedAtUtc = $generated.ToString('o')
        Distribution = 'Workshop-layout local development snapshot'
        PlayableAlpha = $false
        Published = $false
        DeveloperStatus = $statusLine
        RuntimeRoots = @('42', 'common')
        RuntimeFileCount = $runtimeFiles.Count
        RuntimeFiles = @($runtimeFiles.ToArray())
        ExcludedWithinRuntimeRoots = @($excluded.ToArray())
        Files = @($allFiles.ToArray())
        ManifestSelfHashLocation = '../verification.json'
    }
    $manifestPath = Join-Path $packageRoot 'manifest.json'
    Write-Utf8File $manifestPath (($manifest | ConvertTo-Json -Depth 8) + "`n")

    # Explicit enumeration avoids Compress-Archive's hidden-file behavior.
    $archivePath = Assert-WorkspacePath (Join-Path $artifactRoot ($modId + '-' + $Version + '.zip'))
    $archiveStream = [System.IO.File]::Open($archivePath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
    $archive = New-Object System.IO.Compression.ZipArchive($archiveStream, [System.IO.Compression.ZipArchiveMode]::Create, $false)
    try {
        foreach ($file in @(Get-SafeFiles $packageRoot | Sort-Object FullName)) {
            $name = Get-RelativePackagePath $packageRoot $file.FullName
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file.FullName, $name, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
        # Build 42 expects a common directory, including for a mod with no shared assets.
        if (@(Get-ChildItem -LiteralPath (Join-Path $payloadRoot 'common') -Force).Count -eq 0) {
            $archive.CreateEntry('Contents/mods/' + $modId + '/common/') | Out-Null
        }
    }
    finally { $archive.Dispose(); $archiveStream.Dispose() }

    $expected = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($file in @(Get-SafeFiles $packageRoot)) {
        $expected.Add((Get-RelativePackagePath $packageRoot $file.FullName), $file)
    }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $verifiedFileCount = 0
    $archive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        foreach ($entry in $archive.Entries) {
            $name = $entry.FullName
            if ([System.IO.Path]::IsPathRooted($name) -or $name.Contains('\') -or '..' -in $name.Split('/') -or $name.Contains(':')) {
                throw "Unsafe archive entry: $name"
            }
            if (-not $seen.Add($name)) { throw "Duplicate archive entry: $name" }
            if ($name.EndsWith('/')) {
                if ($name -ne ('Contents/mods/' + $modId + '/common/')) { throw "Unexpected directory entry: $name" }
                continue
            }
            if (-not $expected.ContainsKey($name)) { throw "Unexpected archive file: $name" }
            if ($name -notin @('manifest.json', 'README-DEVELOPMENT.txt', 'workshop.txt')) {
                $prefix = 'Contents/mods/' + $modId + '/'
                if (-not $name.StartsWith($prefix, [System.StringComparison]::Ordinal) -or
                    -not (Test-RuntimePath $name.Substring($prefix.Length))) {
                    throw "Archive file is outside the runtime whitelist: $name"
                }
            }
            $entryStream = $entry.Open()
            try { $zipHash = Get-StreamSha256 $entryStream }
            finally { $entryStream.Dispose() }
            if ($entry.Length -ne $expected[$name].Length -or $zipHash -ne (Get-Sha256 $expected[$name].FullName)) {
                throw "Archive content mismatch: $name"
            }
            ++$verifiedFileCount
        }
    }
    finally { $archive.Dispose() }
    if ($verifiedFileCount -ne $expected.Count) { throw 'The archive is missing one or more expected files.' }
    $savedManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    foreach ($record in $savedManifest.Files) {
        if (-not $expected.ContainsKey($record.Path) -or $record.SHA256 -ne (Get-Sha256 $expected[$record.Path].FullName)) {
            throw "Manifest content mismatch: $($record.Path)"
        }
    }
    if ((Get-Content -LiteralPath (Join-Path $packageRoot 'workshop.txt') -Raw) -match '(?im)^\s*(id|publishedid)\s*=') {
        throw 'Publication identifiers must not appear in the development workshop.txt.'
    }

    $verification = [ordered]@{
        SchemaVersion = 1
        Passed = $true
        Scope = 'Runtime whitelist, manifest and ZIP file integrity only; no game acceptance claim'
        Archive = [System.IO.Path]::GetFileName($archivePath)
        ArchiveSHA256 = Get-Sha256 $archivePath
        ManifestSHA256 = Get-Sha256 $manifestPath
        VerifiedFileCount = $verifiedFileCount
        RuntimeFileCount = $runtimeFiles.Count
        PublicationIdentifierPresent = $false
        PlayableAlpha = $false
    }
    Write-Utf8File (Join-Path $artifactRoot 'verification.json') (($verification | ConvertTo-Json -Depth 5) + "`n")
    $completed = $true
    [PSCustomObject]@{
        Passed = $true
        PackageDirectory = $packageRoot
        Archive = $archivePath
        Manifest = $manifestPath
        Verification = Join-Path $artifactRoot 'verification.json'
        RuntimeFiles = $runtimeFiles.Count
        VerifiedArchiveFiles = $verifiedFileCount
        PlayableAlpha = $false
    }
}
catch {
    if ($artifactRoot -and (Test-Path -LiteralPath $artifactRoot -PathType Container) -and -not $completed) {
        $failurePath = Join-Path $artifactRoot 'BUILD-FAILED.txt'
        if (-not (Test-Path -LiteralPath $failurePath)) {
            Write-Utf8File $failurePath ("Incomplete development artifact. Do not use this package.`n" + $_.Exception.Message + "`n")
        }
    }
    throw
}

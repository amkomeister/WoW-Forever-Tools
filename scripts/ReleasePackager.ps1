[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$SourcePath,

    [string]$OutputDirectory = '.\dist',

    [string]$PackageName = 'wow-forever-addon',

    [Parameter(Mandatory = $true)]
    [string]$Version,

    [switch]$Force,

    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression

function Get-SafeRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $relative = $Path.Substring($Root.Length).TrimStart([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar))
    return $relative.Replace([IO.Path]::DirectorySeparatorChar, '/')
}

function Add-TextZipEntry {
    param(
        [Parameter(Mandatory = $true)][IO.Compression.ZipArchive]$Archive,
        [Parameter(Mandatory = $true)][string]$EntryName,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $entry = $Archive.CreateEntry($EntryName, [IO.Compression.CompressionLevel]::Optimal)
    $stream = $null
    $writer = $null
    try {
        $stream = $entry.Open()
        $writer = New-Object IO.StreamWriter($stream, (New-Object Text.UTF8Encoding($false)))
        $writer.Write($Content)
    }
    finally {
        if ($null -ne $writer) { $writer.Dispose() }
        elseif ($null -ne $stream) { $stream.Dispose() }
    }
}

if ($PackageName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') {
    throw 'PackageName may contain only letters, numbers, dots, underscores, and hyphens.'
}
if ($Version -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]{0,31}$') {
    throw 'Version may contain only letters, numbers, dots, underscores, plus signs, and hyphens.'
}

$sourceRoot = (Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).Path
$sourceItem = Get-Item -LiteralPath $sourceRoot -ErrorAction Stop
if (-not $sourceItem.PSIsContainer) {
    throw 'SourcePath must be a directory.'
}

$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
$archiveName = "$PackageName-$Version.zip"
$archivePath = Join-Path $outputRoot $archiveName
$checksumPath = "$archivePath.sha256"

$excludedDirectoryNames = @('.git', '.github', 'tests', 'dist', 'reports', 'WTF', 'SavedVariables')
$files = @(Get-ChildItem -LiteralPath $sourceRoot -File -Recurse -Force | Where-Object {
    $parts = $_.FullName.Substring($sourceRoot.Length).TrimStart([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)) -split '[\\/]'
    $hasExcludedDirectory = @($parts | Where-Object { $excludedDirectoryNames -contains $_ }).Count -gt 0
    -not $hasExcludedDirectory -and $_.Extension -notin @('.zip', '.sha256')
})

foreach ($file in $files) {
    if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "A reparse point was found in the source tree: $($file.Name)"
    }
}

$tocFiles = @($files | Where-Object Extension -ieq '.toc')
if ($tocFiles.Count -eq 0) {
    throw 'The source directory must contain at least one .toc file.'
}

$rootFolder = "$PackageName-$Version"
$manifestLines = New-Object System.Collections.Generic.List[string]
$manifestLines.Add("Package: $PackageName")
$manifestLines.Add("Version: $Version")
$manifestLines.Add('Format: WoW Forever Tools package manifest v1')
$manifestLines.Add('')

foreach ($file in ($files | Sort-Object FullName)) {
    $relative = Get-SafeRelativePath -Root $sourceRoot -Path $file.FullName
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifestLines.Add("$relative`t$hash`t$($file.Length)")
}
$manifest = ($manifestLines -join [Environment]::NewLine) + [Environment]::NewLine

if ($WhatIf) {
    Write-Output "Would create $archivePath"
    Write-Output "Files: $($files.Count)"
    exit 0
}

if ((Test-Path -LiteralPath $archivePath -PathType Leaf) -and -not $Force) {
    throw "The package already exists. Use -Force to replace it: $archivePath"
}

New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$archive = $null
try {
    $archive = [IO.Compression.ZipFile]::Open($archivePath, [IO.Compression.ZipArchiveMode]::Create)
    foreach ($file in ($files | Sort-Object FullName)) {
        $relative = Get-SafeRelativePath -Root $sourceRoot -Path $file.FullName
        $entryName = "$rootFolder/$relative"
        $entry = $archive.CreateEntry($entryName, [IO.Compression.CompressionLevel]::Optimal)
        $input = $null
        $output = $null
        try {
            $input = [IO.File]::OpenRead($file.FullName)
            $output = $entry.Open()
            $input.CopyTo($output)
        }
        finally {
            if ($null -ne $output) { $output.Dispose() }
            if ($null -ne $input) { $input.Dispose() }
        }
    }
    Add-TextZipEntry -Archive $archive -EntryName "$rootFolder/PACKAGE-MANIFEST.txt" -Content $manifest
}
finally {
    if ($null -ne $archive) { $archive.Dispose() }
}

$archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ((Test-Path -LiteralPath $checksumPath -PathType Leaf) -and -not $Force) {
    throw "The checksum file already exists. Use -Force to replace it: $checksumPath"
}
Set-Content -LiteralPath $checksumPath -Value "$archiveHash  $archiveName" -Encoding ASCII

Write-Output "Created $archiveName"
Write-Output "Files: $($files.Count)"
Write-Output "SHA256: $archiveHash"
exit 0

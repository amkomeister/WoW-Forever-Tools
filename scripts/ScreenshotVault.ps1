[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$SourcePath,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$VaultPath,

    [switch]$WhatIf,

    [switch]$SkipIndex
)

$ErrorActionPreference = 'Stop'

function Get-CanonicalDirectoryPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Container) {
        return (Resolve-Path -LiteralPath $Path).Path.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar))
    }
    return [IO.Path]::GetFullPath($Path).TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar))
}

function Test-PathWithin {
    param(
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][string]$Candidate
    )

    $parentWithSeparator = $Parent + [IO.Path]::DirectorySeparatorChar
    return $Candidate.Equals($Parent, [StringComparison]::OrdinalIgnoreCase) -or $Candidate.StartsWith($parentWithSeparator, [StringComparison]::OrdinalIgnoreCase)
}

function Add-ManifestEntry {
    param(
        [Parameter(Mandatory = $true)][object]$List,
        [Parameter(Mandatory = $true)][string]$Hash,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][long]$SizeBytes,
        [Parameter(Mandatory = $true)][string]$ImportedUtc
    )

    $List.Add([pscustomobject]@{
        Sha256 = $Hash
        RelativePath = $RelativePath
        SizeBytes = $SizeBytes
        ImportedUtc = $ImportedUtc
    })
}

function Write-VaultIndex {
    param(
        [Parameter(Mandatory = $true)][string]$VaultRoot,
        [Parameter(Mandatory = $true)][object[]]$Entries
    )

    $items = New-Object System.Collections.Generic.List[string]
    foreach ($entry in ($Entries | Sort-Object RelativePath)) {
        $safePath = [Net.WebUtility]::HtmlEncode([string]$entry.RelativePath)
        $safeDate = [Net.WebUtility]::HtmlEncode(([string]$entry.ImportedUtc))
        $safeSize = [Net.WebUtility]::HtmlEncode(([string]$entry.SizeBytes))
        $items.Add("<li><a href=`"$safePath`">$safePath</a> <small>$safeDate · $safeSize bytes</small></li>")
    }

    $html = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Screenshot Vault</title>
  <style>body{font:16px system-ui,sans-serif;max-width:1100px;margin:2rem auto;padding:0 1rem;background:#111;color:#eee}a{color:#8bd5ff}li{margin:.55rem 0}small{color:#aaa}</style>
</head>
<body>
  <h1>Screenshot Vault</h1>
  <p>$($Entries.Count) unique screenshot(s).</p>
  <ul>
    $($items -join [Environment]::NewLine + '    ')
  </ul>
</body>
</html>
"@
    Set-Content -LiteralPath (Join-Path $VaultRoot 'index.html') -Value $html -Encoding UTF8
}

$allowedExtensions = @('.jpg', '.jpeg', '.png', '.tga', '.webp')
$sourceRoot = Get-CanonicalDirectoryPath -Path $SourcePath
$vaultRoot = Get-CanonicalDirectoryPath -Path $VaultPath
if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
    throw 'SourcePath must be an existing directory.'
}
if ((Test-PathWithin -Parent $sourceRoot -Candidate $vaultRoot) -or (Test-PathWithin -Parent $vaultRoot -Candidate $sourceRoot)) {
    throw 'SourcePath and VaultPath must not contain one another.'
}

$manifestPath = Join-Path $vaultRoot 'manifest.json'
$existingEntries = New-Object System.Collections.Generic.List[object]
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    try {
        $loaded = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        foreach ($entry in @($loaded.Entries)) {
            if ($entry.Sha256 -and $entry.RelativePath) {
                $existingEntries.Add($entry)
            }
        }
    }
    catch {
        throw "The vault manifest is not valid JSON: $manifestPath"
    }
}

$knownHashes = @{}
foreach ($entry in $existingEntries) {
    $knownHashes[[string]$entry.Sha256] = $true
}

$screenshots = @(Get-ChildItem -LiteralPath $sourceRoot -File -Recurse -Force | Where-Object {
    $allowedExtensions -contains $_.Extension.ToLowerInvariant() -and
    (($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)
})
$copied = 0
$duplicates = 0
$entries = New-Object System.Collections.Generic.List[object]
foreach ($entry in $existingEntries) { $entries.Add($entry) }

foreach ($file in ($screenshots | Sort-Object FullName)) {
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($knownHashes.ContainsKey($hash)) {
        $duplicates++
        continue
    }

    $now = [DateTime]::UtcNow
    $relativeDestination = Join-Path (Join-Path $now.ToString('yyyy') $now.ToString('MM')) "$($now.ToString('yyyyMMdd-HHmmssfff'))-$($hash.Substring(0, 8))$($file.Extension.ToLowerInvariant())"
    $relativeDestination = $relativeDestination.Replace([IO.Path]::DirectorySeparatorChar, '/')
    $destination = Join-Path $vaultRoot $relativeDestination
    if (-not $WhatIf) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
    }

    Add-ManifestEntry -List $entries -Hash $hash -RelativePath $relativeDestination -SizeBytes ([long]$file.Length) -ImportedUtc $now.ToString('o')
    $knownHashes[$hash] = $true
    $copied++
}

if (-not $WhatIf) {
    New-Item -ItemType Directory -Path $vaultRoot -Force | Out-Null
    $entryArray = $entries.ToArray()
    $manifestObject = [ordered]@{
        Format = 'Screenshot Vault manifest v1'
        Entries = $entryArray
    }
    $manifestObject | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    if (-not $SkipIndex) {
        Write-VaultIndex -VaultRoot $vaultRoot -Entries $entryArray
    }
}

Write-Output "Screenshot Vault: $(if ($WhatIf) { 'DRY RUN' } else { 'COMPLETE' })"
Write-Output "Screenshots found: $($screenshots.Count)"
Write-Output "Copied: $copied  Duplicates skipped: $duplicates"
if (-not $WhatIf) {
    Write-Output "Vault entries: $($entries.Count)"
}
exit 0

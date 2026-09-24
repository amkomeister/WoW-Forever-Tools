[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$BeforePath,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$AfterPath,

    [ValidateSet('Text', 'Json')]
    [string]$Format = 'Text',

    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

function Get-SavedVariableFiles {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($item.PSIsContainer) {
        return @(Get-ChildItem -LiteralPath $item.FullName -File -Recurse -Filter '*.lua' -Force | Sort-Object FullName)
    }
    return @($item)
}

function Get-DisplayKey {
    param([Parameter(Mandatory = $true)][IO.FileInfo]$File)

    # The key intentionally contains only a filename. Account, realm, character,
    # and local folder names are not copied into the report.
    return $File.Name
}

function Protect-SavedVariablesText {
    param([Parameter(Mandatory = $true)][string]$Text)

    $protected = $Text
    $protected = [regex]::Replace($protected, '(?i)([A-Za-z]:[\\/][^\r\n"'']+|\\\\[^\r\n"'']+)', '<local-path>')
    $protected = [regex]::Replace($protected, '(?im)(["'']?(?:account|accountname|character|char|realm|player|playername|name|server|guild|email|token|username|profile)["'']?\s*=\s*)(["''][^"'']*["''])', '$1"<redacted>"')
    $protected = [regex]::Replace($protected, '(?i)(Users[\\/])[^\\/"'']+', '$1<user>')
    return $protected
}

function Get-RedactedLines {
    param([Parameter(Mandatory = $true)][IO.FileInfo]$File)

    $text = Get-Content -LiteralPath $File.FullName -Raw -ErrorAction Stop
    $protected = Protect-SavedVariablesText -Text $text
    return @($protected -split "`r?`n")
}

function Get-CountMap {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Lines)

    $map = @{}
    foreach ($line in $Lines) {
        if (-not $map.ContainsKey($line)) { $map[$line] = 0 }
        $map[$line]++
    }
    return $map
}

function Get-LineDelta {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Before,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$After
    )

    $beforeCounts = Get-CountMap -Lines $Before
    $afterCounts = Get-CountMap -Lines $After
    $removed = New-Object System.Collections.Generic.List[string]
    $added = New-Object System.Collections.Generic.List[string]

    foreach ($line in $beforeCounts.Keys) {
        $beforeCount = [int]$beforeCounts[$line]
        $afterCount = if ($afterCounts.ContainsKey($line)) { [int]$afterCounts[$line] } else { 0 }
        for ($i = 0; $i -lt ($beforeCount - $afterCount); $i++) { $removed.Add([string]$line) }
    }
    foreach ($line in $afterCounts.Keys) {
        $afterCount = [int]$afterCounts[$line]
        $beforeCount = if ($beforeCounts.ContainsKey($line)) { [int]$beforeCounts[$line] } else { 0 }
        for ($i = 0; $i -lt ($afterCount - $beforeCount); $i++) { $added.Add([string]$line) }
    }

    [pscustomobject]@{
        Added = @($added)
        Removed = @($removed)
    }
}

function Get-Snapshot {
    param([Parameter(Mandatory = $true)][string]$Path)

    $snapshot = @{}
    foreach ($file in (Get-SavedVariableFiles -Path $Path)) {
        $key = Get-DisplayKey -File $file
        if ($snapshot.ContainsKey($key)) {
            $suffix = 2
            do {
                $candidate = "$key#$suffix"
                $suffix++
            } while ($snapshot.ContainsKey($candidate))
            $key = $candidate
        }
        $snapshot[$key] = @(Get-RedactedLines -File $file)
    }
    return $snapshot
}

$before = Get-Snapshot -Path $BeforePath
$after = Get-Snapshot -Path $AfterPath
$allKeys = @($before.Keys + $after.Keys | Sort-Object -Unique)
$fileResults = New-Object System.Collections.Generic.List[object]

foreach ($key in $allKeys) {
    $beforeLines = if ($before.ContainsKey($key)) { @($before[$key]) } else { @() }
    $afterLines = if ($after.ContainsKey($key)) { @($after[$key]) } else { @() }
    $delta = Get-LineDelta -Before $beforeLines -After $afterLines
    if ($delta.Added.Count -gt 0 -or $delta.Removed.Count -gt 0) {
        $fileResults.Add([pscustomobject]@{
            File = [string]$key
            Added = @($delta.Added)
            Removed = @($delta.Removed)
            AddedCount = $delta.Added.Count
            RemovedCount = $delta.Removed.Count
        })
    }
}

$diffStatus = 'UNCHANGED'
if ($fileResults.Count -gt 0) {
    $diffStatus = 'CHANGED'
}
$fileArray = $fileResults.ToArray()
$result = [ordered]@{
    Tool = 'SavedVariables Diff Viewer'
    Status = $diffStatus
    FilesCompared = $allKeys.Count
    ChangedFiles = $fileResults.Count
    Privacy = 'Values for common identity and credential keys, user folders, and local paths are redacted.'
    Files = $fileArray
}

if ($Format -eq 'Json') {
    $rendered = $result | ConvertTo-Json -Depth 8
}
else {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("SavedVariables Diff Viewer: $($result.Status)")
    $lines.Add("Files compared: $($result.FilesCompared)  Changed: $($result.ChangedFiles)")
    foreach ($file in $fileResults) {
        $lines.Add('')
        $lines.Add("[$($file.File)] +$($file.AddedCount) -$($file.RemovedCount)")
        foreach ($line in @($file.Removed | Select-Object -First 100)) { $lines.Add("- $line") }
        foreach ($line in @($file.Added | Select-Object -First 100)) { $lines.Add("+ $line") }
    }
    if ($fileResults.Count -eq 0) {
        $lines.Add('No differences were found after privacy redaction.')
    }
    $rendered = $lines -join [Environment]::NewLine
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $parent = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Set-Content -LiteralPath $OutputPath -Value $rendered -Encoding UTF8
}

Write-Output $rendered
exit 0

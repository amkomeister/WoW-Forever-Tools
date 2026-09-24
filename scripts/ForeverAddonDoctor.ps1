[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$GamePath,

    [string]$OutputPath,

    [int]$ExpectedInterface = 0,

    [switch]$AsJson,

    [switch]$IncludeDisabled
)

$ErrorActionPreference = 'Stop'

function Get-RelativeAddonPath {
    param(
        [Parameter(Mandatory = $true)][string]$AddonRoot,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $relative = $Path.Substring($AddonRoot.Length).TrimStart([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar))
    if ([string]::IsNullOrWhiteSpace($relative)) {
        return '.'
    }

    return $relative.Replace([IO.Path]::DirectorySeparatorChar, '/')
}

function Get-TocMetadata {
    param([Parameter(Mandatory = $true)][string]$Path)

    $metadata = [ordered]@{
        Path = $Path
        Interface = @()
        Title = @()
        Version = @()
        Dependencies = @()
        OptionalDependencies = @()
    }

    foreach ($line in (Get-Content -LiteralPath $Path -ErrorAction Stop)) {
        if ($line -match '^\s*##\s*Interface\s*:\s*(.+?)\s*$') {
            $numbers = [regex]::Matches($Matches[1], '\d+') | ForEach-Object { [int]$_.Value }
            if ($numbers.Count -gt 0) {
                $metadata.Interface += $numbers
            }
        }
        elseif ($line -match '^\s*##\s*Title\s*:\s*(.+?)\s*$') {
            $metadata.Title += $Matches[1].Trim()
        }
        elseif ($line -match '^\s*##\s*Version\s*:\s*(.+?)\s*$') {
            $metadata.Version += $Matches[1].Trim()
        }
        elseif ($line -match '^\s*##\s*Dependencies\s*:\s*(.+?)\s*$') {
            $metadata.Dependencies += @($Matches[1] -split '[,\s]+' | Where-Object { $_ })
        }
        elseif ($line -match '^\s*##\s*OptionalDeps?\s*:\s*(.+?)\s*$') {
            $metadata.OptionalDependencies += @($Matches[1] -split '[,\s]+' | Where-Object { $_ })
        }
    }

    return $metadata
}

function New-DoctorIssue {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Error', 'Warning')][string]$Severity,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][string]$Addon,
        [Parameter(Mandatory = $true)][string]$Message
    )

    [pscustomobject]@{
        Severity = $Severity
        Code = $Code
        Addon = $Addon
        Message = $Message
    }
}

if ([string]::IsNullOrWhiteSpace($GamePath)) {
    if ([Environment]::UserInteractive) {
        $GamePath = Read-Host 'Path to the WoW Forever installation'
    }
    else {
        throw 'GamePath is required when running non-interactively.'
    }
}

$resolvedGamePath = (Resolve-Path -LiteralPath $GamePath -ErrorAction Stop).Path
$addonRoot = Join-Path $resolvedGamePath 'Interface\AddOns'
if (-not (Test-Path -LiteralPath $addonRoot -PathType Container)) {
    throw "The installation does not contain Interface\AddOns."
}

$issues = New-Object System.Collections.Generic.List[object]
$addons = New-Object System.Collections.Generic.List[object]
$addonDirectories = Get-ChildItem -LiteralPath $addonRoot -Directory -Force | Sort-Object Name

foreach ($addonDirectory in $addonDirectories) {
    if (-not $IncludeDisabled -and $addonDirectory.Name -match '\.disabled$') {
        continue
    }

    $addonName = $addonDirectory.Name
    if (($addonDirectory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        $issues.Add((New-DoctorIssue -Severity Error -Code 'REPARSE_POINT' -Addon $addonName -Message 'The addon folder is a reparse point and was skipped.'))
        continue
    }

    $tocFiles = @(Get-ChildItem -LiteralPath $addonDirectory.FullName -File -Filter '*.toc' -Force | Sort-Object Name)
    $nestedTocFiles = @(Get-ChildItem -LiteralPath $addonDirectory.FullName -File -Filter '*.toc' -Force -Recurse | Where-Object { $_.Directory.FullName -ne $addonDirectory.FullName })
    if ($tocFiles.Count -eq 0) {
        $issues.Add((New-DoctorIssue -Severity Warning -Code 'NO_TOC' -Addon $addonName -Message 'No .toc file was found at the addon root.'))
    }
    if ($nestedTocFiles.Count -gt 0) {
        $issues.Add((New-DoctorIssue -Severity Warning -Code 'NESTED_TOC' -Addon $addonName -Message 'One or more .toc files are nested below the addon root.'))
    }

    $addonMetadata = New-Object System.Collections.Generic.List[object]
    foreach ($tocFile in $tocFiles) {
        $metadata = Get-TocMetadata -Path $tocFile.FullName
        $safeMetadata = [ordered]@{
            File = $tocFile.Name
            Interface = @($metadata.Interface | Select-Object -Unique)
            Title = @($metadata.Title | Select-Object -Unique)
            Version = @($metadata.Version | Select-Object -Unique)
            Dependencies = @($metadata.Dependencies | Select-Object -Unique)
            OptionalDependencies = @($metadata.OptionalDependencies | Select-Object -Unique)
        }
        $addonMetadata.Add([pscustomobject]$safeMetadata)

        if ($ExpectedInterface -gt 0 -and $metadata.Interface.Count -gt 0) {
            $hasExpectedInterface = @($metadata.Interface | Where-Object { $_ -eq $ExpectedInterface }).Count -gt 0
            if (-not $hasExpectedInterface) {
                $reported = ($metadata.Interface | Select-Object -Unique) -join ', '
                $issues.Add((New-DoctorIssue -Severity Warning -Code 'INTERFACE_MISMATCH' -Addon $addonName -Message "$($tocFile.Name) declares interface $reported; expected $ExpectedInterface."))
            }
        }
        elseif ($ExpectedInterface -gt 0) {
            $issues.Add((New-DoctorIssue -Severity Warning -Code 'NO_INTERFACE' -Addon $addonName -Message "$($tocFile.Name) does not declare an interface version."))
        }

        foreach ($dependency in $metadata.Dependencies) {
            $dependencyDirectory = Join-Path $addonRoot $dependency
            $dependencyToc = Join-Path $addonRoot "$dependency.toc"
            if (-not (Test-Path -LiteralPath $dependencyDirectory -PathType Container) -and -not (Test-Path -LiteralPath $dependencyToc -PathType Leaf)) {
                $issues.Add((New-DoctorIssue -Severity Warning -Code 'MISSING_DEPENDENCY' -Addon $addonName -Message "$($tocFile.Name) requires '$dependency', which was not found beside this addon."))
            }
        }
    }

    $addons.Add([pscustomobject]@{
        Name = $addonName
        TocFiles = $addonMetadata.ToArray()
    })
}

$duplicateTocNames = $addons.TocFiles.File | Group-Object | Where-Object { $_.Count -gt 1 }
foreach ($duplicate in $duplicateTocNames) {
    $issues.Add((New-DoctorIssue -Severity Warning -Code 'DUPLICATE_TOC_NAME' -Addon '(multiple)' -Message "The .toc filename '$($duplicate.Name)' appears in multiple addon folders."))
}

$errors = @($issues | Where-Object Severity -eq 'Error')
$warnings = @($issues | Where-Object Severity -eq 'Warning')
$expectedInterfaceValue = $null
if ($ExpectedInterface -gt 0) {
    $expectedInterfaceValue = $ExpectedInterface
}
$statusValue = 'PASS'
if ($errors.Count -gt 0) {
    $statusValue = 'FAIL'
}
elseif ($warnings.Count -gt 0) {
    $statusValue = 'WARN'
}
$addonArray = $addons.ToArray()
$issueArray = $issues.ToArray()
$result = [ordered]@{
    Tool = 'Forever Addon Doctor'
    Status = $statusValue
    ExpectedInterface = $expectedInterfaceValue
    AddonCount = $addons.Count
    ErrorCount = $errors.Count
    WarningCount = $warnings.Count
    Addons = $addonArray
    Issues = $issueArray
}

if ($AsJson) {
    $rendered = $result | ConvertTo-Json -Depth 8
}
else {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("Forever Addon Doctor: $($result.Status)")
    $lines.Add("Addons scanned: $($result.AddonCount)")
    $lines.Add("Errors: $($result.ErrorCount)  Warnings: $($result.WarningCount)")
    foreach ($issue in $issues) {
        $lines.Add("[$($issue.Severity)] $($issue.Code) - $($issue.Addon): $($issue.Message)")
    }
    if ($issues.Count -eq 0) {
        $lines.Add('No addon issues were found.')
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
if ($errors.Count -gt 0) {
    exit 1
}
exit 0

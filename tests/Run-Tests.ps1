[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$scriptRoot = Join-Path $repoRoot 'scripts'
$shellCommand = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
$shellPath = (Get-Command $shellCommand -ErrorAction Stop).Source
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('wow-forever-tools-tests-' + [guid]::NewGuid().ToString('N'))

function Assert-True {
    param([Parameter(Mandatory = $true)][bool]$Condition, [Parameter(Mandatory = $true)][string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function Assert-Contains {
    param([Parameter(Mandatory = $true)][string]$Text, [Parameter(Mandatory = $true)][string]$Needle, [Parameter(Mandatory = $true)][string]$Message)
    Assert-True -Condition ($Text.Contains($Needle)) -Message $Message
}

function Invoke-Tool {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $output = @(& $shellPath -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1)
    [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output = ($output | Out-String)
    }
}

New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    # Forever Addon Doctor: healthy, stale, nested, and missing-dependency cases.
    $gameRoot = Join-Path $testRoot 'game'
    $good = Join-Path $gameRoot 'Interface\AddOns\GoodAddon'
    $bad = Join-Path $gameRoot 'Interface\AddOns\BadAddon'
    $nested = Join-Path $gameRoot 'Interface\AddOns\NestedAddon\sub'
    New-Item -ItemType Directory -Path $good, $bad, $nested -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $good 'GoodAddon.toc') -Value "## Interface: 12345`n## Title: Good Addon" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $bad 'BadAddon.toc') -Value "## Interface: 99999`n## Dependencies: MissingAddon" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $nested 'Nested.toc') -Value "## Interface: 12345" -Encoding UTF8
    $doctor = Invoke-Tool -ScriptPath (Join-Path $scriptRoot 'ForeverAddonDoctor.ps1') -Arguments @('-GamePath', $gameRoot, '-ExpectedInterface', '12345')
    Assert-True ($doctor.ExitCode -eq 0) 'Addon Doctor should return success for warnings-only findings.'
    Assert-Contains $doctor.Output 'INTERFACE_MISMATCH' 'Addon Doctor should identify stale interface versions.'
    Assert-Contains $doctor.Output 'MISSING_DEPENDENCY' 'Addon Doctor should identify missing required dependencies.'
    Assert-Contains $doctor.Output 'NESTED_TOC' 'Addon Doctor should identify nested TOC files.'

    # Release Packager: create a deterministic, privacy-safe archive and checksum.
    $addonSource = Join-Path $testRoot 'addon-source'
    $packageOutput = Join-Path $testRoot 'packages'
    New-Item -ItemType Directory -Path (Join-Path $addonSource 'SavedVariables') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $addonSource 'Example.toc') -Value '## Interface: 12345' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $addonSource 'Main.lua') -Value 'print("hello")' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $addonSource 'SavedVariables\skip.lua') -Value 'private' -Encoding UTF8
    $packager = Invoke-Tool -ScriptPath (Join-Path $scriptRoot 'ReleasePackager.ps1') -Arguments @('-SourcePath', $addonSource, '-OutputDirectory', $packageOutput, '-PackageName', 'example-addon', '-Version', '1.0.0', '-Force')
    Assert-True ($packager.ExitCode -eq 0) 'Release Packager should complete successfully.'
    $archivePath = Join-Path $packageOutput 'example-addon-1.0.0.zip'
    $checksumPath = "$archivePath.sha256"
    Assert-True (Test-Path -LiteralPath $archivePath) 'Release Packager should create a ZIP archive.'
    Assert-True (Test-Path -LiteralPath $checksumPath) 'Release Packager should create a checksum sidecar.'
    $archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $entryNames = @($archive.Entries | ForEach-Object FullName)
        Assert-True ($entryNames -contains 'example-addon-1.0.0/Example.toc') 'Package should contain addon files.'
        Assert-True ($entryNames -contains 'example-addon-1.0.0/PACKAGE-MANIFEST.txt') 'Package should contain a manifest.'
        Assert-True (-not ($entryNames -like '*SavedVariables*')) 'Package must exclude SavedVariables.'
        $manifestEntry = $archive.GetEntry('example-addon-1.0.0/PACKAGE-MANIFEST.txt')
        $reader = New-Object IO.StreamReader($manifestEntry.Open())
        try { $manifestText = $reader.ReadToEnd() } finally { $reader.Dispose() }
        Assert-True (-not $manifestText.Contains($testRoot)) 'Package manifest must not contain local paths.'
    }
    finally { $archive.Dispose() }

    # Screenshot Vault: copy, deduplicate, and index without modifying the source.
    $screenshotSource = Join-Path $testRoot 'screenshots'
    $vault = Join-Path $testRoot 'vault'
    New-Item -ItemType Directory -Path $screenshotSource -Force | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $screenshotSource 'one.png'), [byte[]](1, 2, 3, 4))
    [IO.File]::WriteAllBytes((Join-Path $screenshotSource 'duplicate.jpg'), [byte[]](1, 2, 3, 4))
    $vaultRun = Invoke-Tool -ScriptPath (Join-Path $scriptRoot 'ScreenshotVault.ps1') -Arguments @('-SourcePath', $screenshotSource, '-VaultPath', $vault)
    Assert-True ($vaultRun.ExitCode -eq 0) 'Screenshot Vault should complete successfully.'
    $vaultManifest = Get-Content -LiteralPath (Join-Path $vault 'manifest.json') -Raw | ConvertFrom-Json
    Assert-True (@($vaultManifest.Entries).Count -eq 1) 'Screenshot Vault should deduplicate identical content.'
    Assert-True (Test-Path -LiteralPath (Join-Path $vault 'index.html')) 'Screenshot Vault should generate an HTML index.'
    Assert-True (Test-Path -LiteralPath (Join-Path $screenshotSource 'one.png')) 'Screenshot Vault must leave source files in place.'

    # SavedVariables Diff Viewer: compare redacted values without exposing identity or local paths.
    $beforeRoot = Join-Path $testRoot 'before'
    $afterRoot = Join-Path $testRoot 'after'
    New-Item -ItemType Directory -Path (Join-Path $beforeRoot 'AccountA\CharacterOne'), (Join-Path $afterRoot 'AccountA\CharacterOne') -Force | Out-Null
    $beforeText = @'
MyAddonDB = {
  account = "AccountA",
  player = "CharacterOne",
  path = "C:\Users\Private\Saved",
  value = 1
}
'@
    $afterText = $beforeText.Replace('value = 1', 'value = 2').Replace('CharacterOne', 'CharacterTwo')
    Set-Content -LiteralPath (Join-Path $beforeRoot 'AccountA\CharacterOne\state.lua') -Value $beforeText -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $afterRoot 'AccountA\CharacterOne\state.lua') -Value $afterText -Encoding UTF8
    $diffRun = Invoke-Tool -ScriptPath (Join-Path $scriptRoot 'SavedVariablesDiff.ps1') -Arguments @('-BeforePath', $beforeRoot, '-AfterPath', $afterRoot, '-Format', 'Json')
    Assert-True ($diffRun.ExitCode -eq 0) 'SavedVariables Diff Viewer should complete successfully.'
    Assert-Contains $diffRun.Output 'redacted' 'Diff output should state that identity values are redacted.'
    Assert-Contains $diffRun.Output 'value = 2' 'Diff output should retain useful non-identity changes.'
    Assert-True (-not $diffRun.Output.Contains('AccountA')) 'Diff output must not expose account folder names.'
    Assert-True (-not $diffRun.Output.Contains('C:\Users')) 'Diff output must not expose local paths.'

    Write-Output "PASS: all WoW Forever Tools tests passed under $($PSVersionTable.PSVersion)."
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}

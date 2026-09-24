# WoW Forever Tools

Safe, local PowerShell QoL tools for auditing, packaging, archiving, and comparing World of Warcraft: Forever addons and settings.

The tools are independent scripts. They do not automate gameplay, connect to a game account, or upload files. They work with Windows PowerShell 5.1 and PowerShell 7 without third-party modules.

## Included tools

### Forever Addon Doctor

Audits an `Interface\AddOns` folder for missing `.toc` files, stale interface versions, nested TOC files, reparse points, and missing required dependencies. It reports findings and does not change the game installation.

```powershell
pwsh -NoProfile -File .\scripts\ForeverAddonDoctor.ps1 `
  -GamePath 'C:\Games\WoW Forever' `
  -ExpectedInterface 12345 `
  -OutputPath .\reports\addons.txt
```

Use `-AsJson` for a machine-readable report. The report contains addon metadata and relative filenames, not the installation path.

### Release Packager

Creates a reproducible ZIP and SHA-256 sidecar for an addon. It includes addon files and a package manifest while excluding `.git`, test folders, `WTF`, `SavedVariables`, existing archives, and checksum files.

```powershell
pwsh -NoProfile -File .\scripts\ReleasePackager.ps1 `
  -SourcePath 'C:\Work\MyAddon' `
  -PackageName my-addon `
  -Version 1.0.0 `
  -OutputDirectory .\dist
```

Add `-WhatIf` to preview the archive path and file count. Use `-Force` to replace an existing package.

### Screenshot Vault

Copies PNG, JPG, JPEG, TGA, and WEBP screenshots into a dated local vault, deduplicates identical files by SHA-256, and builds a small offline `index.html`. It never deletes or moves source screenshots.

```powershell
pwsh -NoProfile -File .\scripts\ScreenshotVault.ps1 `
  -SourcePath 'C:\Screenshots\WoW' `
  -VaultPath 'D:\WoW-Screenshot-Vault'
```

The vault manifest stores hashes, vault-relative paths, sizes, and UTC import times. Original source paths and names are not written to the manifest.

### SavedVariables Diff Viewer

Compares one SavedVariables file or two folders of `.lua` files. It gives a useful text or JSON diff while redacting common identity and credential keys, user folder names, and local Windows paths.

```powershell
pwsh -NoProfile -File .\scripts\SavedVariablesDiff.ps1 `
  -BeforePath 'C:\Backups\Before\WTF' `
  -AfterPath 'C:\Backups\After\WTF' `
  -Format Text `
  -OutputPath .\reports\savedvariables-diff.txt
```

Diff output is intended for local review. Always inspect a report before sharing it; game settings can still contain names or other values that are not covered by the built-in redaction rules.

## Download and run

Download the repository as a ZIP from GitHub, extract it, and run the script you need from PowerShell. No installer is required. If Windows blocks a downloaded script, review it first and run it with an execution policy appropriate for your machine:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

The scripts are read-only with respect to the game installation except for the explicit output paths supplied to them. Release Packager writes only its package output; Screenshot Vault copies files into the vault you choose.

For a full, step-by-step walkthrough covering installation, setup, each command, updates, and removal, see [Getting started](docs/GETTING-STARTED.md).

## Privacy and safety

- No telemetry, account login, network calls, or game-process access.
- Reports and vaults are local artifacts. Do not commit real screenshots, SavedVariables, logs, or generated archives to a public repository.
- Release Packager refuses reparse points and excludes common private/runtime folders.
- SavedVariables Diff Viewer performs redaction before rendering output, but it cannot know every addon-specific secret. Review output before sharing.

## Development

Run the cross-shell test suite from the repository root:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

GitHub Actions runs the same suite on Windows PowerShell 5.1 and PowerShell 7 for pushes and pull requests.

## License

MIT. See [LICENSE](LICENSE).

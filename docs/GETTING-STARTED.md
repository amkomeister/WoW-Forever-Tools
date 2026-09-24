# Getting started

This guide walks through downloading, setting up, using, and removing WoW Forever Tools. The project is portable: there is no installer, service, background process, or account connection.

## 1. Requirements

- Windows 10 or newer.
- Windows PowerShell 5.1 (included with Windows) or PowerShell 7.
- Read access to the addon, screenshot, or SavedVariables folder you want to inspect.
- Write access only to the report, package, or vault folder you choose.

## 2. Download and set up the tools

1. Open the repository on GitHub and choose **Code → Download ZIP**.
2. Extract the ZIP to a folder you control, such as `C:\Tools\WoW-Forever-Tools`.
3. Open PowerShell in that extracted folder. In File Explorer, use **Open in Terminal**, or run:

   ```powershell
   Set-Location 'C:\Tools\WoW-Forever-Tools'
   ```

4. Confirm that the four scripts exist:

   ```powershell
   Get-ChildItem .\scripts\*.ps1
   ```

5. Run the local test suite once. It uses synthetic data and does not read your game folders:

   ```powershell
   .\tests\Run-Tests.ps1
   ```

   A successful run prints `PASS` and the PowerShell version used.

The scripts do not need to be copied into the WoW Forever installation. Keep the tools folder separate from the game folder so it can be updated or removed independently.

## 3. Allow a downloaded script for this session

If Windows reports that script execution is disabled, inspect the files first and then allow scripts only in the current PowerShell process:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

This does not change the machine or user execution policy. Close the PowerShell window to remove the temporary setting.

## 4. Use Forever Addon Doctor

1. Find the WoW Forever folder. It is the folder that contains `Interface\AddOns`.
2. Run the audit, replacing the example path and interface number with the values for your client:

   ```powershell
   .\scripts\ForeverAddonDoctor.ps1 `
     -GamePath 'C:\Games\WoW Forever' `
     -ExpectedInterface 12345 `
     -OutputPath .\reports\addons.txt
   ```

3. Read the `PASS`, `WARN`, or `FAIL` header and then each issue code.
4. Fix addon files or dependencies manually, then run the audit again.
5. Add `-AsJson` when another tool needs structured output.

The doctor never edits the game installation. A warning is informational; an error is reserved for an unsafe folder such as a reparse point.

## 5. Create a release with Release Packager

1. Put the addon source in its own folder. The folder must contain at least one `.toc` file.
2. Keep private runtime data outside that source folder, or rely on the built-in exclusions for `WTF`, `SavedVariables`, test folders, `.git`, and existing archives.
3. Preview the package first:

   ```powershell
   .\scripts\ReleasePackager.ps1 `
     -SourcePath 'C:\Work\MyAddon' `
     -PackageName my-addon `
     -Version 1.0.0 `
     -OutputDirectory .\dist `
     -WhatIf
   ```

4. Remove `-WhatIf` to create `my-addon-1.0.0.zip` and its `.sha256` file.
5. Use `-Force` only when you intentionally want to replace an existing package.
6. Upload or share the ZIP and checksum, not the source folder or generated private data.

The archive contains a relative-path manifest and SHA-256 hashes. It does not record the local source path.

## 6. Build a Screenshot Vault

1. Choose a source folder containing screenshots and a separate destination folder for the vault. The two folders must not contain one another.
2. Run:

   ```powershell
   .\scripts\ScreenshotVault.ps1 `
     -SourcePath 'C:\Screenshots\WoW' `
     -VaultPath 'D:\WoW-Screenshot-Vault'
   ```

3. Open `index.html` in the vault folder to browse the copied images offline.
4. Run the same command later to import new screenshots. Identical files are skipped by SHA-256.
5. Back up or delete the vault folder like any other local photo archive.

The source screenshots are never moved or deleted. The manifest stores only vault-relative paths, hashes, sizes, and UTC import times.

## 7. Compare SavedVariables safely

1. Make two copies of the SavedVariables folder: one before a change and one after it.
2. Close the game or addon manager before copying so the files are complete.
3. Compare the folders:

   ```powershell
   .\scripts\SavedVariablesDiff.ps1 `
     -BeforePath 'C:\Backups\Before\WTF' `
     -AfterPath 'C:\Backups\After\WTF' `
     -Format Text `
     -OutputPath .\reports\savedvariables-diff.txt
   ```

4. Use `-Format Json` for automation.
5. Review the report locally before sharing it. Common account, character, realm, identity, credential, user-folder, and Windows-path values are redacted before the diff is rendered. Other addon-specific values may still be personal.

The viewer does not execute Lua and does not modify either input folder.

## 8. Update or remove the tools

To update a ZIP download, download the newest repository ZIP and replace the old tools folder after closing PowerShell windows that use it. If you use Git, run `git pull` from the repository folder.

To remove the tools, delete the extracted repository folder. The scripts do not install files elsewhere, create registry entries, or run in the background. Remove generated artifacts separately only when you know the paths are yours:

```powershell
Remove-Item -LiteralPath 'C:\Tools\WoW-Forever-Tools' -Recurse -Force
Remove-Item -LiteralPath 'D:\WoW-Screenshot-Vault' -Recurse -Force
```

Deleting the tools folder does not remove addons, screenshots, game settings, or any other folder supplied as an input. Deleting a vault or report folder is permanent, so check the resolved path before running a cleanup command.

## Troubleshooting

- **`Interface\AddOns` was not found:** pass the game installation folder, not the `AddOns` folder itself.
- **The packager says no `.toc` file was found:** point `-SourcePath` at the addon root and confirm the file extension is `.toc`.
- **The vault rejects the paths:** choose two separate folders; a vault inside its source could recursively import its own output.
- **The diff is empty:** make sure the inputs are different snapshots and that they contain `.lua` files.
- **A report contains a value you do not want to share:** delete the report, change the input or redaction rule, and rerun it. Never publish real game data while troubleshooting.

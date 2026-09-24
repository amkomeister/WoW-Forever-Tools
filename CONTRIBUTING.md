# Contributing

Thanks for helping improve WoW Forever Tools.

Keep scripts compatible with Windows PowerShell 5.1 and PowerShell 7. Avoid network access, telemetry, game-process automation, and writes outside paths explicitly supplied by the user. Do not commit screenshots, SavedVariables, logs, local reports, archives, or machine-specific paths.

Before opening a pull request, run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

Please describe the user-facing behavior, safety boundaries, and test result in the pull request description.

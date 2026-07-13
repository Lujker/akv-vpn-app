# Backward-compatible entry point. New builds should use build_windows.ps1 directly.
& (Join-Path $PSScriptRoot 'build_windows.ps1') @args
exit $LASTEXITCODE

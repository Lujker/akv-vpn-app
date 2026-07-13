<#
.SYNOPSIS
Builds and packages AKV VPN for Windows.

.DESCRIPTION
Prepares Dart code, downloads the production Windows core when needed, builds the
release application and creates a portable ZIP and an EXE installer. MSIX is opt-in
because it requires windows\sign.pfx.

.EXAMPLE
.\scripts\build_windows.ps1

.EXAMPLE
.\scripts\build_windows.ps1 -Clean -Targets portable,exe

.EXAMPLE
.\scripts\build_windows.ps1 -Targets all
#>
[CmdletBinding()]
param(
    [switch]$Clean,
    [ValidateSet('portable', 'exe', 'msix', 'all')]
    [string[]]$Targets = @('portable', 'exe')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Native {
    param(
        [Parameter(Mandatory)]
        [string]$Description,
        [Parameter(Mandatory)]
        [string]$Command,
        [string[]]$Arguments = @()
    )

    Write-Host ">> $Description"
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE."
    }
}

if ($env:OS -ne 'Windows_NT') {
    throw 'This script must be run in native Windows PowerShell, not WSL.'
}

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

foreach ($command in @('flutter', 'dart', 'tar.exe')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command '$command' was not found in PATH. See docs/private/BUILD_RU.md."
    }
}

$flutterVersionLine = (& flutter --version | Select-Object -First 1)
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to determine the Flutter version.'
}
if ($flutterVersionLine -match 'Flutter ([0-9]+\.[0-9]+\.[0-9]+)') {
    $flutterVersion = [version]$Matches[1]
    if ($flutterVersion.Major -ne 3 -or $flutterVersion.Minor -lt 38 -or $flutterVersion.Minor -gt 43) {
        Write-Warning "Flutter $flutterVersion is not verified. Use Flutter 3.38.x; 3.44+ breaks pinned dependencies."
    }
}

$resolvedTargets = if ($Targets -contains 'all') { @('portable', 'exe', 'msix') } else { $Targets | Select-Object -Unique }

if ($resolvedTargets -contains 'msix' -and -not (Test-Path 'windows\sign.pfx')) {
    throw 'MSIX packaging requires windows\sign.pfx and a matching publisher value in windows\packaging\msix\make_config.yaml.'
}

if ($Clean) {
    Invoke-Native -Description 'flutter clean' -Command 'flutter' -Arguments @('clean')
}

Invoke-Native -Description 'flutter pub get' -Command 'flutter' -Arguments @('pub', 'get')
Invoke-Native -Description 'code generation (build_runner)' -Command 'dart' -Arguments @('run', 'build_runner', 'build', '--delete-conflicting-outputs')
Invoke-Native -Description 'translation generation (slang)' -Command 'dart' -Arguments @('run', 'slang')

$corePath = 'hiddify-core\bin\hiddify-core.dll'
if (-not (Test-Path $corePath)) {
    $coreVersionLine = Get-Content 'dependencies.properties' | Where-Object { $_ -match '^core\.version=' } | Select-Object -First 1
    if (-not $coreVersionLine) {
        throw 'core.version is missing from dependencies.properties.'
    }
    $coreVersion = ($coreVersionLine -split '=', 2)[1]
    $archive = Join-Path $env:TEMP "hiddify-lib-windows-amd64-$coreVersion.tar.gz"
    $url = "https://github.com/hiddify/hiddify-next-core/releases/download/v$coreVersion/hiddify-lib-windows-amd64.tar.gz"

    try {
        New-Item -ItemType Directory -Force -Path 'hiddify-core\bin' | Out-Null
        Write-Host ">> Downloading production hiddify-core v$coreVersion"
        Invoke-WebRequest -Uri $url -OutFile $archive
        Invoke-Native -Description 'extracting hiddify-core' -Command 'tar.exe' -Arguments @('-xzf', $archive, '-C', 'hiddify-core\bin')
    }
    finally {
        Remove-Item -Force -ErrorAction SilentlyContinue $archive
    }
}
else {
    Write-Host '>> hiddify-core.dll already present, skipping download.'
}

Invoke-Native -Description 'Flutter Windows release build' -Command 'flutter' -Arguments @('build', 'windows', '--release', '--target', 'lib/main.dart')

$runnerOutput = 'build\windows\x64\runner\Release'
if (-not (Test-Path $runnerOutput)) {
    throw "Windows runner output not found: $runnerOutput"
}

Remove-Item -Recurse -Force -ErrorAction SilentlyContinue 'dist'
New-Item -ItemType Directory -Force -Path 'dist', 'out' | Out-Null
Get-ChildItem -Path 'out' -File -Filter 'AKV-VPN-Windows-*' -ErrorAction SilentlyContinue |
    Remove-Item -Force

if ($resolvedTargets -contains 'portable') {
    $portableDir = 'dist\AKV-VPN-Windows-Portable-x64'
    $portableZip = 'out\AKV-VPN-Windows-Portable-x64.zip'
    New-Item -ItemType Directory -Force -Path $portableDir | Out-Null
    Copy-Item -Recurse -Force "$runnerOutput\*" $portableDir
    Compress-Archive -Force -Path $portableDir -DestinationPath $portableZip
    Write-Host ">> Portable package: $portableZip"
}

function Copy-FastforgeArtifact {
    param(
        [Parameter(Mandatory)]
        [string]$Extension,
        [Parameter(Mandatory)]
        [string]$Destination
    )

    $artifact = Get-ChildItem -Path 'dist' -Recurse -File -Filter "*.$Extension" |
        Sort-Object LastWriteTime |
        Select-Object -Last 1
    if (-not $artifact) {
        throw "Fastforge did not create a .$Extension package."
    }
    Copy-Item -Force $artifact.FullName $Destination
    Write-Host ">> Package: $Destination"
}

if ($resolvedTargets -contains 'exe') {
    Invoke-Native -Description 'Fastforge installation' -Command 'dart' -Arguments @('pub', 'global', 'activate', 'fastforge')
    Invoke-Native -Description 'Fastforge EXE packaging' -Command 'dart' -Arguments @('pub', 'global', 'run', 'fastforge:fastforge', 'package', '--platform', 'windows', '--targets', 'exe', '--skip-clean', '--build-target', 'lib/main.dart')
    Copy-FastforgeArtifact -Extension 'exe' -Destination 'out\AKV-VPN-Windows-Setup-x64.exe'
}

if ($resolvedTargets -contains 'msix') {
    if (-not ($resolvedTargets -contains 'exe')) {
        Invoke-Native -Description 'Fastforge installation' -Command 'dart' -Arguments @('pub', 'global', 'activate', 'fastforge')
    }
    Invoke-Native -Description 'Fastforge MSIX packaging' -Command 'dart' -Arguments @('pub', 'global', 'run', 'fastforge:fastforge', 'package', '--platform', 'windows', '--targets', 'msix', '--skip-clean', '--build-target', 'lib/main.dart')
    Copy-FastforgeArtifact -Extension 'msix' -Destination 'out\AKV-VPN-Windows-Setup-x64.msix'
}

Write-Host "`n== Artifacts =="
Get-ChildItem -File 'out' | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize

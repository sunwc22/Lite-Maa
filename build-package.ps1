param(
    [string]$OutputDir = (Join-Path $PSScriptRoot "dist\MaaLite"),
    [switch]$IncludeRuntime,
    [switch]$BuildExe,
    [string]$RuntimeSource = "D:\Applications\PaddleOCR\.venv",
    [string]$PaddleCacheSource = "D:\Applications\PaddleOCR\cache"
)

$ErrorActionPreference = "Stop"

function Ensure-Directory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Copy-ProjectFile {
    param(
        [string]$Name,
        [string]$DestinationRoot
    )

    $source = Join-Path $PSScriptRoot $Name
    if (Test-Path -LiteralPath $source) {
        Copy-Item -LiteralPath $source -Destination (Join-Path $DestinationRoot $Name) -Force
    } else {
        Write-Warning "Skipped missing file: $Name"
    }
}

$packageRoot = $OutputDir
$runtimeRoot = Join-Path $packageRoot "runtime"
$dataRoot = Join-Path $packageRoot "data"
$configRoot = Join-Path $packageRoot "config"
$screenshotsRoot = Join-Path $packageRoot "screenshots"

foreach ($dir in @($packageRoot, $runtimeRoot, $dataRoot, $configRoot, $screenshotsRoot)) {
    Ensure-Directory -Path $dir
}

$projectFiles = @(
    "Arknights-MuMu-Launcher.ps1",
    "Launcher.UI.ps1",
    "Launcher.UI.modern.v2.ps1",
    "Arknights-MuMu-Launcher.vbs",
    "vision_detect.py",
    "duel_dataset.py",
    "mumu_capture.py",
    "AGENTS.md"
)

foreach ($file in $projectFiles) {
    Copy-ProjectFile -Name $file -DestinationRoot $packageRoot
}

$datasetSource = Join-Path $PSScriptRoot "data\duel_match_dataset.jsonl"
if (-not (Test-Path -LiteralPath $datasetSource)) {
    $datasetSource = Join-Path $PSScriptRoot "duel_match_dataset.jsonl"
}
if (Test-Path -LiteralPath $datasetSource) {
    Copy-Item -LiteralPath $datasetSource -Destination (Join-Path $dataRoot "duel_match_dataset.jsonl") -Force
}

$settingsExample = [pscustomobject]@{
    MuMuRoot = "E:\game_my\MuMuPlayer-12.0"
    VmIndex = 0
    Package = "com.hypergryph.arknights"
}
($settingsExample | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath (Join-Path $configRoot "settings.example.json") -Encoding UTF8

if ($IncludeRuntime) {
    if (-not (Test-Path -LiteralPath $RuntimeSource)) {
        throw "Runtime source not found: $RuntimeSource"
    }
    if (-not (Test-Path -LiteralPath $PaddleCacheSource)) {
        throw "Paddle cache source not found: $PaddleCacheSource"
    }

    $runtimeDestination = Join-Path $runtimeRoot "python"
    $cacheDestination = Join-Path $runtimeRoot "paddle-cache"
    Ensure-Directory -Path $runtimeDestination
    Ensure-Directory -Path $cacheDestination

    Write-Host "Copying Python/PaddleOCR runtime. This may take several minutes..."
    Copy-Item -Path (Join-Path $RuntimeSource "*") -Destination $runtimeDestination -Recurse -Force

    Write-Host "Copying PaddleOCR cache..."
    Copy-Item -Path (Join-Path $PaddleCacheSource "*") -Destination $cacheDestination -Recurse -Force
} else {
    Write-Host "Runtime not included. Run with -IncludeRuntime to copy PaddleOCR into runtime\python and runtime\paddle-cache."
}

if ($BuildExe) {
    $inputScript = Join-Path $packageRoot "Arknights-MuMu-Launcher.ps1"
    $outputExe = Join-Path $packageRoot "MaaLite.exe"
    $invokePs2Exe = Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue
    $ps2exe = Get-Command ps2exe -ErrorAction SilentlyContinue

    if ($invokePs2Exe) {
        Invoke-ps2exe -InputFile $inputScript -OutputFile $outputExe -NoConsole -STA
        Write-Host "Built exe: $outputExe"
    } elseif ($ps2exe) {
        & $ps2exe -InputFile $inputScript -OutputFile $outputExe -NoConsole -STA
        Write-Host "Built exe: $outputExe"
    } else {
        Write-Warning "ps2exe is not installed. Install the ps2exe module, then rerun with -BuildExe."
    }
}

$readme = @"
Maa Lite portable package

Run:
  1. Prefer double-clicking Arknights-MuMu-Launcher.vbs.
  2. If MaaLite.exe exists, you can run MaaLite.exe instead.

Portable OCR:
  - If this package was built with -IncludeRuntime, OCR uses:
    runtime\python\Scripts\python.exe
    runtime\paddle-cache
  - If runtime is not included, the app falls back to:
    D:\Applications\PaddleOCR\.venv\Scripts\python.exe
    D:\Applications\PaddleOCR\cache

MuMu path:
  - On first run, if MuMu is not found automatically, select the MuMuPlayer-12.0 root folder.
  - The selected path is saved in config\settings.json.

Data:
  - Duel records are written to data\duel_match_dataset.jsonl.
  - Screenshots are written to screenshots\.
"@
$readme | Set-Content -LiteralPath (Join-Path $packageRoot "README.txt") -Encoding UTF8

Write-Host "Package prepared: $packageRoot"

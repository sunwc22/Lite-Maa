$ErrorActionPreference = "Stop"

$consoleApi = @"
[DllImport("kernel32.dll")]
public static extern IntPtr GetConsoleWindow();

[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
"@

try {
    Add-Type -Namespace Win32 -Name ConsoleWindow -MemberDefinition $consoleApi -ErrorAction SilentlyContinue
    $consoleHandle = [Win32.ConsoleWindow]::GetConsoleWindow()
    if ($consoleHandle -ne [IntPtr]::Zero) {
        [Win32.ConsoleWindow]::ShowWindow($consoleHandle, 0) | Out-Null
    }
} catch {
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Resolve-AppRoot {
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        return $PSScriptRoot
    }

    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
        return (Split-Path -Parent $PSCommandPath)
    }

    if ($MyInvocation.MyCommand.Path -and -not [string]::IsNullOrWhiteSpace($MyInvocation.MyCommand.Path)) {
        return (Split-Path -Parent $MyInvocation.MyCommand.Path)
    }

    $processPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    if (-not [string]::IsNullOrWhiteSpace($processPath)) {
        return (Split-Path -Parent $processPath)
    }

    return (Get-Location).Path
}

$appRoot = Resolve-AppRoot
$VmIndex = 0
$Package = "com.hypergryph.arknights"
$configDir = Join-Path $appRoot "config"
$dataDir = Join-Path $appRoot "data"
$runtimeDir = Join-Path $appRoot "runtime"
$portablePython = Join-Path $runtimeDir "python\Scripts\python.exe"
$fallbackOcrPython = "D:\Applications\PaddleOCR\.venv\Scripts\python.exe"
$portablePaddleCache = Join-Path $runtimeDir "paddle-cache"
$fallbackPaddleCache = "D:\Applications\PaddleOCR\cache"
$settingsPath = Join-Path $configDir "settings.json"

foreach ($dir in @($configDir, $dataDir, (Join-Path $appRoot "screenshots"))) {
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function Get-PortablePython {
    if (Test-Path -LiteralPath $portablePython) {
        return $portablePython
    }
    if (Test-Path -LiteralPath $fallbackOcrPython) {
        return $fallbackOcrPython
    }
    return "python"
}

function Get-PaddleCachePath {
    if (Test-Path -LiteralPath $portablePaddleCache) {
        return $portablePaddleCache
    }
    return $fallbackPaddleCache
}

function Test-MuMuRoot {
    param([string]$Path)

    if (-not $Path) {
        return $false
    }
    return (
        (Test-Path -LiteralPath (Join-Path $Path "nx_main\MuMuManager.exe")) -and
        (Test-Path -LiteralPath (Join-Path $Path "nx_main\MuMuNxMain.exe")) -and
        (Test-Path -LiteralPath (Join-Path $Path "nx_main\adb.exe"))
    )
}

function Get-ConfiguredMuMuRoot {
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        return $null
    }

    try {
        $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($settings.PSObject.Properties.Name -contains "MuMuRoot" -and (Test-MuMuRoot -Path ([string]$settings.MuMuRoot))) {
            return [string]$settings.MuMuRoot
        }
    } catch {
    }

    return $null
}

function Save-ConfiguredMuMuRoot {
    param([string]$Path)

    if (-not (Test-MuMuRoot -Path $Path)) {
        return
    }

    if (-not (Test-Path -LiteralPath $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    $settings = [pscustomobject]@{
        MuMuRoot = $Path
        VmIndex = $VmIndex
        Package = $Package
    }
    ($settings | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $settingsPath -Encoding UTF8
}

function Resolve-MuMuRoot {
    $configured = Get-ConfiguredMuMuRoot
    if ($configured) {
        return $configured
    }

    $candidates = @(
        "E:\game_my\MuMuPlayer-12.0",
        "D:\game_my\MuMuPlayer-12.0",
        "C:\Program Files\Netease\MuMuPlayer-12.0",
        "C:\Program Files\MuMuPlayer-12.0",
        "D:\Applications\MuMuPlayer-12.0",
        "D:\MuMuPlayer-12.0",
        "E:\MuMuPlayer-12.0"
    )

    foreach ($candidate in $candidates) {
        if (Test-MuMuRoot -Path $candidate) {
            Save-ConfiguredMuMuRoot -Path $candidate
            return $candidate
        }
    }

    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select the MuMuPlayer-12.0 root folder containing nx_main\MuMuManager.exe"
    $dialog.ShowNewFolderButton = $false
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK -and (Test-MuMuRoot -Path $dialog.SelectedPath)) {
        Save-ConfiguredMuMuRoot -Path $dialog.SelectedPath
        return $dialog.SelectedPath
    }

    return "E:\game_my\MuMuPlayer-12.0"
}

$MuMuRoot = Resolve-MuMuRoot

$manager = Join-Path $MuMuRoot "nx_main\MuMuManager.exe"
$main = Join-Path $MuMuRoot "nx_main\MuMuNxMain.exe"
$adb = Join-Path $MuMuRoot "nx_main\adb.exe"
$screenshotDir = Join-Path $appRoot "screenshots"
$screenFile = Join-Path $screenshotDir "arknights-mumu-screen.png"
$visionScript = Join-Path $appRoot "vision_detect.py"
$mumuCaptureScript = Join-Path $appRoot "mumu_capture.py"
$duelDatasetScript = Join-Path $appRoot "duel_dataset.py"
$legacyDuelDatasetPath = Join-Path $appRoot "duel_match_dataset.jsonl"
$duelDatasetPath = Join-Path $dataDir "duel_match_dataset.jsonl"
$scriptPython = Get-PortablePython
$duelOcrPython = $scriptPython
$paddleCachePath = Get-PaddleCachePath
$screenIntervalSeconds = 1
$script:captureModeLogged = $false
$script:mumuCaptureDisabled = $false
$script:stopRequested = $false

if ((Test-Path -LiteralPath $legacyDuelDatasetPath) -and -not (Test-Path -LiteralPath $duelDatasetPath)) {
    Copy-Item -LiteralPath $legacyDuelDatasetPath -Destination $duelDatasetPath -Force
}

function Test-StopRequested {
    [System.Windows.Forms.Application]::DoEvents()
    if ($script:stopRequested) {
        throw "Task stopped by user."
    }
}

function Wait-TaskInterval {
    param([double]$Seconds)

    $deadline = (Get-Date).AddMilliseconds([int]($Seconds * 1000))
    while ((Get-Date) -lt $deadline) {
        Test-StopRequested
        Start-Sleep -Milliseconds 100
    }
}

function Add-Log {
    param([string]$Message)

    $line = "[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message
    $logBox.AppendText($line + [Environment]::NewLine)
    $logBox.SelectionStart = $logBox.TextLength
    $logBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-Busy {
    param([bool]$Busy)

    $launchButton.Enabled = -not $Busy
    $stopButton.Enabled = $Busy
    if ($Busy) {
        $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
    } else {
        $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
        $progressBar.Value = 0
    }
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-MuMuInfo {
    $infoText = & $manager info --vmindex $VmIndex 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $infoText) {
        return $null
    }

    try {
        return ($infoText | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Invoke-MuMu {
    param([string[]]$Arguments)

    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & $manager @Arguments 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }

    if ($output) {
        Add-Log (($output -join " ").Trim())
    }
    return $code
}

function Get-AdbSerial {
    $info = Get-MuMuInfo
    if ($info -and $info.PSObject.Properties.Name -contains "adb_host_ip" -and $info.PSObject.Properties.Name -contains "adb_port") {
        return ("{0}:{1}" -f $info.adb_host_ip, $info.adb_port)
    }

    return "127.0.0.1:16384"
}

function Invoke-Adb {
    param([string[]]$Arguments)

    $serial = Get-AdbSerial
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & $adb -s $serial @Arguments 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }

    $isNoisyPull = ($Arguments.Count -ge 1 -and $Arguments[0] -eq "pull" -and $code -eq 0)
    if ($output -and -not $isNoisyPull) {
        Add-Log (($output -join " ").Trim())
    }

    return $code
}

function Get-ForegroundPackage {
    $serial = Get-AdbSerial
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $windowText = & $adb -s $serial shell dumpsys window 2>$null
        $activityText = & $adb -s $serial shell dumpsys activity activities 2>$null
    } finally {
        $ErrorActionPreference = $oldPreference
    }

    $joined = (($windowText + $activityText) -join "`n")
    $focusPatterns = @(
        "mCurrentFocus=.*com\.hypergryph\.arknights",
        "mFocusedApp=.*com\.hypergryph\.arknights",
        "topResumedActivity=.*com\.hypergryph\.arknights",
        "ResumedActivity:.*com\.hypergryph\.arknights"
    )
    foreach ($pattern in $focusPatterns) {
        if ($joined -match $pattern) {
            return $Package
        }
    }

    if ($joined -match "VisibleActivityProcess:.*com\.hypergryph\.arknights" -and $joined -match "mTopFullscreenOpaqueWindowState=.*com\.hypergryph\.arknights") {
        return $Package
    }

    return ""
}

function Wait-ArknightsForeground {
    Add-Log "Waiting for Arknights foreground before vision detection."
    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline) {
        Test-StopRequested
        $foreground = Get-ForegroundPackage
        if ($foreground -eq $Package) {
            Add-Log "Arknights is in foreground; vision detection enabled."
            return
        }
        Wait-TaskInterval -Seconds 1
    }

    throw "Arknights was not in foreground before timeout."
}

function Wait-AdbReady {
    if (-not (Test-Path -LiteralPath $adb)) {
        throw "adb.exe not found: $adb"
    }

    $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Date) -lt $deadline) {
        Test-StopRequested
        $serial = Get-AdbSerial
        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $devices = & $adb devices 2>$null
            if (($devices -join "`n") -match [regex]::Escape($serial) + "\s+offline") {
                Add-Log "ADB is offline; reconnecting."
                & $adb disconnect $serial 2>&1 | Out-Null
                Wait-TaskInterval -Seconds 1
            }

            & $adb connect $serial 2>&1 | Out-Null
        } finally {
            $ErrorActionPreference = $oldPreference
        }

        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $boot = & $adb -s $serial shell getprop sys.boot_completed 2>$null
            $bootCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $oldPreference
        }

        if ($bootCode -eq 0 -and (($boot -join "").Trim() -eq "1")) {
            Add-Log "ADB is ready."
            return
        }

        Wait-TaskInterval -Seconds 2
    }

    throw "ADB was not ready before timeout."
}

function Tap-Screen {
    param(
        [int]$X,
        [int]$Y,
        [string]$Reason
    )

    Test-StopRequested
    Add-Log ("Tap {0},{1} {2}" -f $X, $Y, $Reason)
    Invoke-Adb -Arguments @("shell", "input", "tap", "$X", "$Y") | Out-Null
}

function Tap-ScreenBurst {
    param(
        [int]$X,
        [int]$Y,
        [string]$Reason
    )

    Tap-Screen -X $X -Y $Y -Reason $Reason
    Wait-TaskInterval -Seconds 0.25
    Tap-Screen -X $X -Y $Y -Reason "$Reason retry"
}

function Close-BlockingOverlay {
    param([object]$Vision)

    $size = Get-DeviceSize
    if ($Vision -and $Vision.PSObject.Properties.Name -contains "state" -and [string]$Vision.state -eq "announcement" -and $Vision.PSObject.Properties.Name -contains "x" -and $Vision.PSObject.Properties.Name -contains "y") {
        Add-Log ("Announcement detected; tapping close at {0},{1}." -f $Vision.x, $Vision.y)
        Tap-Screen -X ([int]$Vision.x) -Y ([int]$Vision.y) -Reason "close announcement"
        return
    }

    $points = @(
        @{ X = [int]($size.Width * 0.94); Y = [int]($size.Height * 0.10); Name = "top-right close area" },
        @{ X = [int]($size.Width * 0.06); Y = [int]($size.Height * 0.10); Name = "top-left empty area" },
        @{ X = [int]($size.Width * 0.50); Y = [int]($size.Height * 0.94); Name = "bottom empty area" }
    )
    foreach ($point in $points) {
        Add-Log ("Trying to close overlay via {0}." -f $point.Name)
        Tap-Screen -X $point.X -Y $point.Y -Reason "close overlay"
        Wait-TaskInterval -Seconds 0.35
        Test-StopRequested
    }
}

function Get-DeviceSize {
    $serial = Get-AdbSerial
    $sizeText = & $adb -s $serial shell wm size 2>$null
    $joined = ($sizeText -join " ")
    if ($joined -match "(\d+)x(\d+)") {
        $a = [int]$Matches[1]
        $b = [int]$Matches[2]
        return @{
            Width = [Math]::Max($a, $b)
            Height = [Math]::Min($a, $b)
        }
    }

    return @{
        Width = 1920
        Height = 1080
    }
}

function Capture-Screen {
    Test-StopRequested
    if (-not $script:mumuCaptureDisabled -and (Test-Path -LiteralPath $mumuCaptureScript)) {
        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $output = & $scriptPython $mumuCaptureScript $MuMuRoot $VmIndex $Package $screenFile 2>&1
            $code = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $oldPreference
        }

        $jsonLine = ($output | Where-Object { $_ -and $_.ToString().Trim().StartsWith("{") } | Select-Object -Last 1)
        if ($code -eq 0 -and $jsonLine) {
            try {
                $result = $jsonLine | ConvertFrom-Json
                if ($result.ok -and (Test-Path -LiteralPath $screenFile)) {
                    if (-not $script:captureModeLogged) {
                        Add-Log ("Screenshot: MuMu enhanced mode, {0}x{1}, {2} ms." -f $result.width, $result.height, $result.cost_ms)
                        $script:captureModeLogged = $true
                    }
                    return $screenFile
                }
            } catch {
            }
        }

        $script:mumuCaptureDisabled = $true
        $message = "MuMu enhanced screenshot failed; falling back to ADB."
        if ($jsonLine) {
            try {
                $result = $jsonLine | ConvertFrom-Json
                if ($result.PSObject.Properties.Name -contains "error" -and $result.error) {
                    $message = "MuMu enhanced screenshot failed: $($result.error). Falling back to ADB."
                }
            } catch {
            }
        }
        Add-Log $message
    }

    $remoteFile = "/sdcard/arknights-mumu-screen.png"
    Invoke-Adb -Arguments @("shell", "screencap", "-p", $remoteFile) | Out-Null
    Invoke-Adb -Arguments @("pull", $remoteFile, $screenFile) | Out-Null

    if (-not (Test-Path -LiteralPath $screenFile)) {
        throw "Screenshot failed."
    }

    return $screenFile
}

function Invoke-VisionDetect {
    param([string]$Path)

    Test-StopRequested
    if (-not (Test-Path -LiteralPath $visionScript)) {
        throw "Vision script not found: $visionScript"
    }

    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & $scriptPython $visionScript $Path 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $oldPreference
    }

    if ($code -ne 0) {
        throw "Vision detector failed: $($output -join ' ')"
    }

    $jsonLine = ($output | Where-Object { $_ -and $_.ToString().Trim().StartsWith("{") } | Select-Object -Last 1)
    if (-not $jsonLine) {
        throw "Vision detector returned no JSON."
    }

    try {
        return ($jsonLine | ConvertFrom-Json)
    } catch {
        throw "Vision detector returned invalid JSON: $jsonLine"
    }
}

function Save-DuelMatchDataset {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $duelDatasetScript)) {
        throw "Duel dataset script not found: $duelDatasetScript"
    }

    $pythonExe = $scriptPython
    if (Test-Path -LiteralPath $duelOcrPython) {
        $pythonExe = $duelOcrPython
    }

    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $oldPaddleCache = $env:PADDLE_PDX_CACHE_HOME
        $oldPaddleOnednn = $env:FLAGS_use_onednn
        $oldPaddleMkldnn = $env:FLAGS_use_mkldnn
        $oldPaddlePir = $env:FLAGS_enable_pir_api
        $env:PADDLE_PDX_CACHE_HOME = $paddleCachePath
        $env:FLAGS_use_onednn = "0"
        $env:FLAGS_use_mkldnn = "0"
        $env:FLAGS_enable_pir_api = "0"
        $output = & $pythonExe $duelDatasetScript --extract $Path 2>&1
        $code = $LASTEXITCODE
    } finally {
        $env:PADDLE_PDX_CACHE_HOME = $oldPaddleCache
        $env:FLAGS_use_onednn = $oldPaddleOnednn
        $env:FLAGS_use_mkldnn = $oldPaddleMkldnn
        $env:FLAGS_enable_pir_api = $oldPaddlePir
        $ErrorActionPreference = $oldPreference
    }

    $jsonLine = ($output | Where-Object { $_ -and $_.ToString().Trim().StartsWith("{") } | Select-Object -Last 1)
    if ($code -ne 0 -or -not $jsonLine) {
        throw "Duel dataset extraction failed: $($output -join ' ')"
    }

    $result = $jsonLine | ConvertFrom-Json
    if (-not $result.ok) {
        throw "Duel dataset extraction failed."
    }

    if ($result.PSObject.Properties.Name -contains "skipped" -and [bool]$result.skipped) {
        $reason = "no usable enemy detail"
        if ($result.PSObject.Properties.Name -contains "reason" -and $result.reason) {
            $reason = [string]$result.reason
        }
        Add-Log ("Duel dataset skipped: {0}." -f $reason)
        return $null
    }

    $fieldCount = 0
    if ($result.PSObject.Properties.Name -contains "fields" -and $result.fields) {
        $fieldCount = @($result.fields).Count
    }
    Add-Log ("Duel matchup recognized: {0} field(s)." -f $fieldCount)
    return $result
}

function Invoke-DuelGiftDetect {
    param([string]$Path)

    $pythonExe = $scriptPython
    if (Test-Path -LiteralPath $duelOcrPython) {
        $pythonExe = $duelOcrPython
    }

    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $oldPaddleCache = $env:PADDLE_PDX_CACHE_HOME
        $oldPaddleOnednn = $env:FLAGS_use_onednn
        $oldPaddleMkldnn = $env:FLAGS_use_mkldnn
        $oldPaddlePir = $env:FLAGS_enable_pir_api
        $env:PADDLE_PDX_CACHE_HOME = $paddleCachePath
        $env:FLAGS_use_onednn = "0"
        $env:FLAGS_use_mkldnn = "0"
        $env:FLAGS_enable_pir_api = "0"
        $output = & $pythonExe $duelDatasetScript --gift $Path 2>&1
        $code = $LASTEXITCODE
    } finally {
        $env:PADDLE_PDX_CACHE_HOME = $oldPaddleCache
        $env:FLAGS_use_onednn = $oldPaddleOnednn
        $env:FLAGS_use_mkldnn = $oldPaddleMkldnn
        $env:FLAGS_enable_pir_api = $oldPaddlePir
        $ErrorActionPreference = $oldPreference
    }

    $jsonLine = ($output | Where-Object { $_ -and $_.ToString().Trim().StartsWith("{") } | Select-Object -Last 1)
    if ($code -ne 0 -or -not $jsonLine) {
        Add-Log ("Gift OCR failed: {0}" -f (($output -join " ").Trim()))
        return $null
    }

    try {
        return ($jsonLine | ConvertFrom-Json)
    } catch {
        Add-Log "Gift OCR returned invalid JSON."
        return $null
    }
}

function Invoke-DuelFinalGiftDetect {
    param([string]$Path)

    $pythonExe = $scriptPython
    if (Test-Path -LiteralPath $duelOcrPython) {
        $pythonExe = $duelOcrPython
    }

    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $oldPaddleCache = $env:PADDLE_PDX_CACHE_HOME
        $oldPaddleOnednn = $env:FLAGS_use_onednn
        $oldPaddleMkldnn = $env:FLAGS_use_mkldnn
        $oldPaddlePir = $env:FLAGS_enable_pir_api
        $env:PADDLE_PDX_CACHE_HOME = $paddleCachePath
        $env:FLAGS_use_onednn = "0"
        $env:FLAGS_use_mkldnn = "0"
        $env:FLAGS_enable_pir_api = "0"
        $output = & $pythonExe $duelDatasetScript --final-gift $Path 2>&1
        $code = $LASTEXITCODE
    } finally {
        $env:PADDLE_PDX_CACHE_HOME = $oldPaddleCache
        $env:FLAGS_use_onednn = $oldPaddleOnednn
        $env:FLAGS_use_mkldnn = $oldPaddleMkldnn
        $env:FLAGS_enable_pir_api = $oldPaddlePir
        $ErrorActionPreference = $oldPreference
    }

    $jsonLine = ($output | Where-Object { $_ -and $_.ToString().Trim().StartsWith("{") } | Select-Object -Last 1)
    if ($code -ne 0 -or -not $jsonLine) {
        Add-Log ("Final gift OCR failed: {0}" -f (($output -join " ").Trim()))
        return $null
    }

    try {
        return ($jsonLine | ConvertFrom-Json)
    } catch {
        Add-Log "Final gift OCR returned invalid JSON."
        return $null
    }
}

function Test-DuelFinalGiftEvidence {
    param([object]$FinalGift)

    if (-not $FinalGift -or -not ($FinalGift.PSObject.Properties.Name -contains "score")) {
        return $false
    }
    $text = [string]$FinalGift.score
    $finalGiftLabel = -join @([char]0x6700, [char]0x7EC8, [char]0x793C, [char]0x7269, [char]0x70B9, [char]0x6570)
    $giftPointLabel = -join @([char]0x793C, [char]0x7269, [char]0x70B9, [char]0x6570)
    return ($text.Contains($finalGiftLabel) -or $text.Contains($giftPointLabel))
}

function Invoke-DuelSupportButtonDetect {
    param(
        [string]$Path,
        [string]$Side
    )

    $pythonExe = $scriptPython
    if (Test-Path -LiteralPath $duelOcrPython) {
        $pythonExe = $duelOcrPython
    }

    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $oldPaddleCache = $env:PADDLE_PDX_CACHE_HOME
        $oldPaddleOnednn = $env:FLAGS_use_onednn
        $oldPaddleMkldnn = $env:FLAGS_use_mkldnn
        $oldPaddlePir = $env:FLAGS_enable_pir_api
        $env:PADDLE_PDX_CACHE_HOME = $paddleCachePath
        $env:FLAGS_use_onednn = "0"
        $env:FLAGS_use_mkldnn = "0"
        $env:FLAGS_enable_pir_api = "0"
        $output = & $pythonExe $duelDatasetScript --support-button $Side $Path 2>&1
        $code = $LASTEXITCODE
    } finally {
        $env:PADDLE_PDX_CACHE_HOME = $oldPaddleCache
        $env:FLAGS_use_onednn = $oldPaddleOnednn
        $env:FLAGS_use_mkldnn = $oldPaddleMkldnn
        $env:FLAGS_enable_pir_api = $oldPaddlePir
        $ErrorActionPreference = $oldPreference
    }

    $jsonLine = ($output | Where-Object { $_ -and $_.ToString().Trim().StartsWith("{") } | Select-Object -Last 1)
    if ($code -ne 0 -or -not $jsonLine) {
        Add-Log ("Support button OCR failed: {0}" -f (($output -join " ").Trim()))
        return $null
    }

    try {
        return ($jsonLine | ConvertFrom-Json)
    } catch {
        Add-Log "Support button OCR returned invalid JSON."
        return $null
    }
}

function Get-RegionYellowRatio {
    param(
        [string]$Path,
        [double]$Left,
        [double]$Top,
        [double]$Right,
        [double]$Bottom
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return 0.0
    }

    $bitmap = [System.Drawing.Bitmap]::FromFile($Path)
    try {
        $w = $bitmap.Width
        $h = $bitmap.Height
        $x1 = [Math]::Max(0, [int]($w * $Left))
        $y1 = [Math]::Max(0, [int]($h * $Top))
        $x2 = [Math]::Min($w - 1, [int]($w * $Right))
        $y2 = [Math]::Min($h - 1, [int]($h * $Bottom))
        $step = [Math]::Max(3, [int]($w / 360))
        $samples = 0
        $yellow = 0

        for ($y = $y1; $y -le $y2; $y += $step) {
            for ($x = $x1; $x -le $x2; $x += $step) {
                $p = $bitmap.GetPixel($x, $y)
                if ($p.R -gt 180 -and $p.G -gt 145 -and $p.B -lt 120) {
                    $yellow++
                }
                $samples++
            }
        }

        return ($yellow / [Math]::Max(1, $samples))
    } finally {
        $bitmap.Dispose()
    }
}

function Test-DuelSupportSubmitted {
    param([string]$Path)

    $leftButtonYellow = Get-RegionYellowRatio -Path $Path -Left 0.02 -Top 0.82 -Right 0.24 -Bottom 0.97
    $rightButtonYellow = Get-RegionYellowRatio -Path $Path -Left 0.76 -Top 0.82 -Right 0.98 -Bottom 0.97
    $toastYellow = Get-RegionYellowRatio -Path $Path -Left 0.38 -Top 0.84 -Right 0.62 -Bottom 0.96

    if ($toastYellow -gt 0.12) {
        Add-Log ("Support submitted: center confirmation toast detected ({0:N2})." -f $toastYellow)
        return $true
    }

    if ($leftButtonYellow -lt 0.10 -and $rightButtonYellow -lt 0.10) {
        Add-Log ("Support submitted: support buttons disappeared (L {0:N2}, R {1:N2})." -f $leftButtonYellow, $rightButtonYellow)
        return $true
    }

    Add-Log ("Support not confirmed yet (L {0:N2}, R {1:N2}, toast {2:N2})." -f $leftButtonYellow, $rightButtonYellow, $toastYellow)
    return $false
}

function Add-DuelMatchRecord {
    param(
        [object]$MatchResult,
        [string]$WinnerSide
    )

    $matchRecord = $null
    if ($MatchResult -and $MatchResult.PSObject.Properties.Name -contains "record") {
        $matchRecord = $MatchResult.record
    }

    if ($null -eq $matchRecord) {
        Add-Log "Duel match record missing; result was not saved."
        return
    }

    $timeLocal = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")

    $leftEnemies = @()
    if ($matchRecord.PSObject.Properties.Name -contains "left_enemies" -and $matchRecord.left_enemies) {
        foreach ($enemy in @($matchRecord.left_enemies)) {
            $leftEnemies += [pscustomobject]@{
                name = [string]$enemy.name
                count = $enemy.count
            }
        }
    }

    $rightEnemies = @()
    if ($matchRecord.PSObject.Properties.Name -contains "right_enemies" -and $matchRecord.right_enemies) {
        foreach ($enemy in @($matchRecord.right_enemies)) {
            $rightEnemies += [pscustomobject]@{
                name = [string]$enemy.name
                count = $enemy.count
            }
        }
    }

    $ocrQuality = Get-DuelMatchRecognitionQuality -MatchResult $MatchResult
    $enemyOcrStatus = if ($ocrQuality.IsComplete) { "complete" } else { "incomplete" }
    $compactRecord = [pscustomobject]@{
        time_local = $timeLocal
        winner_side = $WinnerSide
        enemy_ocr_status = $enemyOcrStatus
        left = $leftEnemies
        right = $rightEnemies
    }

    ($compactRecord | ConvertTo-Json -Depth 8 -Compress) | Add-Content -LiteralPath $duelDatasetPath -Encoding UTF8
    Add-Log ("Duel match appended with winner_side: {0}, enemy_ocr_status: {1}." -f $WinnerSide, $enemyOcrStatus)
}

function Get-DuelMatchRecognitionQuality {
    param([object]$MatchResult)

    $quality = [pscustomobject]@{
        IsUsable = $false
        IsComplete = $false
        EnemyCount = 0
        MissingCount = 0
        MissingName = 0
        LeftCount = 0
        RightCount = 0
        Score = -1000
    }

    if (-not $MatchResult -or -not ($MatchResult.PSObject.Properties.Name -contains "record") -or -not $MatchResult.record) {
        return $quality
    }

    $record = $MatchResult.record
    $leftEnemies = @()
    $rightEnemies = @()
    if ($record.PSObject.Properties.Name -contains "left_enemies" -and $record.left_enemies) {
        $leftEnemies = @($record.left_enemies)
    }
    if ($record.PSObject.Properties.Name -contains "right_enemies" -and $record.right_enemies) {
        $rightEnemies = @($record.right_enemies)
    }

    $quality.LeftCount = $leftEnemies.Count
    $quality.RightCount = $rightEnemies.Count
    $quality.EnemyCount = $quality.LeftCount + $quality.RightCount
    foreach ($enemy in @($leftEnemies + $rightEnemies)) {
        $name = ""
        if ($enemy.PSObject.Properties.Name -contains "name" -and $null -ne $enemy.name) {
            $name = ([string]$enemy.name).Trim()
        }
        if (-not $name) {
            $quality.MissingName++
        }
        if (-not ($enemy.PSObject.Properties.Name -contains "count") -or $null -eq $enemy.count) {
            $quality.MissingCount++
        }
    }

    $quality.IsUsable = ($quality.EnemyCount -gt 0)
    $quality.IsComplete = ($quality.LeftCount -gt 0 -and $quality.RightCount -gt 0 -and $quality.MissingName -eq 0 -and $quality.MissingCount -eq 0)
    $quality.Score = ($quality.EnemyCount * 10) - ($quality.MissingCount * 4) - ($quality.MissingName * 6)
    if ($quality.LeftCount -eq 0 -or $quality.RightCount -eq 0) {
        $quality.Score -= 20
    }
    return $quality
}

function New-FallbackDuelMatchResult {
    param([Nullable[int]]$RemainingGifts)

    $record = [pscustomobject]@{
        timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
        mode = "duel_casual"
        source_image = $null
        ocr_available = $true
        ocr_error = ""
        ocr_engine = "paddleocr"
        remaining_gifts = $RemainingGifts
        left_enemies = @()
        right_enemies = @()
        left_enemy_total = $null
        right_enemy_total = $null
        note = "matchup detail not captured"
    }

    return [pscustomobject]@{
        ok = $true
        fields = @()
        record = $record
    }
}

function Wait-DuelResult {
    param(
        [object]$MatchResult,
        [string]$SupportSide,
        [Nullable[int]]$InitialGifts
    )

    Add-Log "Waiting for duel result by watching remaining gifts; battle may take 10-60 seconds."
    $finalGifts = $null
    $sawFinalSettlement = $false
    $deadline = (Get-Date).AddMinutes(6)
    $pollDelaySeconds = 10
    while ((Get-Date) -lt $deadline) {
        Test-StopRequested
        Wait-TaskInterval -Seconds $pollDelaySeconds
        $pollDelaySeconds = 5
        $path = Capture-Screen

        $vision = Invoke-VisionDetect -Path $path
        $visionConfidence = 0.0
        if ($vision.PSObject.Properties.Name -contains "confidence") {
            $visionConfidence = [double]$vision.confidence
        }
        $visionState = [string]$vision.state
        if ($visionState -eq "duel_result" -and $visionConfidence -ge 0.95) {
            Add-Log ("Final settlement page detected while waiting for gift change (confidence {0:N2}, method {1})." -f $visionConfidence, $vision.method)
            $finalGift = Invoke-DuelFinalGiftDetect -Path $path
            if ($finalGift -and $finalGift.PSObject.Properties.Name -contains "remaining_gifts" -and $null -ne $finalGift.remaining_gifts) {
                $finalGifts = [int]$finalGift.remaining_gifts
                Add-Log ("Final settlement gifts detected: {0}." -f $finalGifts)
            }
            $sawFinalSettlement = $true
            break
        }

        $gift = Invoke-DuelGiftDetect -Path $path
        if ($gift -and $gift.PSObject.Properties.Name -contains "remaining_gifts" -and $null -ne $gift.remaining_gifts) {
            $current = [int]$gift.remaining_gifts
            $finalGifts = $current
            Add-Log ("Remaining gifts detected: {0}." -f $current)
            if ($null -ne $InitialGifts -and $current -ne $InitialGifts) {
                Add-Log ("Duel settlement detected: gifts changed from {0} to {1}." -f $InitialGifts, $current)
                break
            }
        }

        if ($visionState -eq "duel_result" -or $visionState -eq "duel_game" -or $visionState -eq "start" -or $visionState -eq "unknown") {
            $finalGift = Invoke-DuelFinalGiftDetect -Path $path
            if ((Test-DuelFinalGiftEvidence -FinalGift $finalGift) -and $finalGift.PSObject.Properties.Name -contains "remaining_gifts" -and $null -ne $finalGift.remaining_gifts) {
                $finalGifts = [int]$finalGift.remaining_gifts
                Add-Log ("Final settlement confirmed by OCR while waiting for gift change: {0} gifts." -f $finalGifts)
                $sawFinalSettlement = $true
                break
            }
        }
    }

    $winnerSide = "unknown"
    if ($null -ne $InitialGifts -and $null -ne $finalGifts) {
        if ($finalGifts -gt $InitialGifts) {
            $winnerSide = $SupportSide
        } elseif ($SupportSide -eq "left") {
            $winnerSide = "right"
        } elseif ($SupportSide -eq "right") {
            $winnerSide = "left"
        }
    }

    Add-DuelMatchRecord -MatchResult $MatchResult -WinnerSide $winnerSide
    if ($sawFinalSettlement) {
        Return-DuelHomeAfterResult
    }
    return [pscustomobject]@{
        SawFinalSettlement = $sawFinalSettlement
        WinnerSide = $winnerSide
    }
}

function Return-DuelHomeAfterResult {
    Add-Log "Waiting for duel result page return button."
    $deadline = (Get-Date).AddSeconds(45)
    while ((Get-Date) -lt $deadline) {
        Test-StopRequested
        $path = Capture-Screen
        $vision = Invoke-VisionDetect -Path $path
        $state = [string]$vision.state

        if ($state -eq "duel_channel" -or $state -eq "duel_event_select" -or $state -eq "duel_casual_selected") {
            Add-Log ("Duel navigation page detected after result: {0}." -f $state)
            return
        }

        if ($state -eq "duel_result") {
            $confidence = 0.0
            if ($vision.PSObject.Properties.Name -contains "confidence") {
                $confidence = [double]$vision.confidence
            }
            if ($confidence -lt 0.95) {
                $finalGift = Invoke-DuelFinalGiftDetect -Path $path
                if (Test-DuelFinalGiftEvidence -FinalGift $finalGift) {
                    Add-Log ("Low-confidence result return page confirmed by final gift OCR (confidence {0:N2})." -f $confidence)
                } else {
                    Add-Log "Low-confidence result return page ignored."
                    Wait-TaskInterval -Seconds 2
                    continue
                }
            }
            $x = [int]$vision.x
            $y = [int]$vision.y
            Add-Log ("Duel result page detected; tapping return home at {0},{1}." -f $x, $y)
            Tap-ScreenBurst -X $x -Y $y -Reason "duel return home"
            Wait-TaskInterval -Seconds 2.0
            continue
        }

        if ($state -eq "start" -or $state -eq "unknown" -or $state -eq "home") {
            $finalGift = Invoke-DuelFinalGiftDetect -Path $path
            if (Test-DuelFinalGiftEvidence -FinalGift $finalGift) {
                $size = Get-DeviceSize
                $x = [int]($size.Width * 0.875)
                $y = [int]($size.Height * 0.92)
                Add-Log ("Final settlement return confirmed by OCR despite state {0}; tapping return home at {1},{2}." -f $state, $x, $y)
                Tap-ScreenBurst -X $x -Y $y -Reason "duel return home OCR fallback"
                Wait-TaskInterval -Seconds 2.0
                continue
            }
        }

        Add-Log ("Waiting for result return page, current state: {0}." -f $state)
        Wait-TaskInterval -Seconds 2
    }

    Add-Log "Result return page was not confirmed; continuing navigation loop."
}

function Random-SupportDuelSide {
    param([object]$MatchResult)

    $size = Get-DeviceSize
    $side = if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) { "left" } else { "right" }
    if ($side -eq "left") {
        $points = @(
            @{ X = [int]($size.Width * 0.13); Y = [int]($size.Height * 0.89); Name = "left support center" },
            @{ X = [int]($size.Width * 0.12); Y = [int]($size.Height * 0.83); Name = "left support label" },
            @{ X = [int]($size.Width * 0.07); Y = [int]($size.Height * 0.88); Name = "left support all" }
        )
    } else {
        $points = @(
            @{ X = [int]($size.Width * 0.87); Y = [int]($size.Height * 0.89); Name = "right support center" },
            @{ X = [int]($size.Width * 0.88); Y = [int]($size.Height * 0.83); Name = "right support label" },
            @{ X = [int]($size.Width * 0.93); Y = [int]($size.Height * 0.88); Name = "right support all" }
        )
    }

    $initialGifts = $null
    if ($MatchResult -and $MatchResult.PSObject.Properties.Name -contains "record" -and $MatchResult.record.PSObject.Properties.Name -contains "remaining_gifts" -and $null -ne $MatchResult.record.remaining_gifts) {
        $initialGifts = [int]$MatchResult.record.remaining_gifts
    }

    Add-Log ("Random support selected: {0}, initial gifts {1}." -f $side, $initialGifts)
    $path = Capture-Screen
    $button = Invoke-DuelSupportButtonDetect -Path $path -Side $side
    if ($button -and $button.PSObject.Properties.Name -contains "found" -and [bool]$button.found) {
        $buttonText = ""
        if ($button.PSObject.Properties.Name -contains "text") {
            $buttonText = [string]$button.text
        }
        Add-Log ("Support button OCR hit: {0} at {1},{2}." -f $buttonText, $button.x, $button.y)
        $points = ,@{ X = [int]$button.x; Y = [int]$button.y; Name = ("OCR " + $buttonText) } + $points
    } else {
        Add-Log "Support button OCR missed; using fallback tap points."
    }

    foreach ($point in $points) {
        Test-StopRequested
        Tap-ScreenBurst -X $point.X -Y $point.Y -Reason ("support " + $point.Name)
        Wait-TaskInterval -Seconds 1.20

        $path = Capture-Screen
        if (Test-DuelSupportSubmitted -Path $path) {
            Add-Log "Support tap confirmed."
            break
        }
    }
    return (Wait-DuelResult -MatchResult $MatchResult -SupportSide $side -InitialGifts $initialGifts)
}

function Collect-DuelMatchInfo {
    Add-Log "Collecting duel matchup dataset."
    $size = Get-DeviceSize

    $detailPoints = @(
        @{ X = [int]($size.Width * 0.39); Y = [int]($size.Height * 0.90); Name = "left bottom enemy icon 1" },
        @{ X = [int]($size.Width * 0.45); Y = [int]($size.Height * 0.90); Name = "left bottom enemy icon 2" },
        @{ X = [int]($size.Width * 0.57); Y = [int]($size.Height * 0.90); Name = "right bottom enemy icon 1" },
        @{ X = [int]($size.Width * 0.63); Y = [int]($size.Height * 0.90); Name = "right bottom enemy icon 2" }
    )

    $oldScreenFile = $screenFile
    $captureIndex = 0
    foreach ($point in $detailPoints) {
        Test-StopRequested
        Add-Log ("Opening {0}." -f $point.Name)
        Tap-Screen -X $point.X -Y $point.Y -Reason "duel enemy detail"
        Wait-TaskInterval -Seconds 0.50

        $captureIndex++
        $datasetScreen = Join-Path $screenshotDir ("arknights-duel-dataset-{0}-{1}.png" -f (Get-Date -Format "yyyyMMdd-HHmmss"), $captureIndex)
        try {
            $script:screenFile = $datasetScreen
            $path = Capture-Screen
            $savedResult = Save-DuelMatchDataset -Path $path
            if ($null -ne $savedResult) {
                $quality = Get-DuelMatchRecognitionQuality -MatchResult $savedResult
                $status = if ($quality.IsComplete) { "complete" } else { "incomplete" }
                Add-Log ("Duel OCR quality: {0}, enemies {1}, missing count {2}, missing name {3}, sides L{4}/R{5}." -f $status, $quality.EnemyCount, $quality.MissingCount, $quality.MissingName, $quality.LeftCount, $quality.RightCount)
                Add-Log "Duel matchup captured; stopping further recognition for this task."
                return (Random-SupportDuelSide -MatchResult $savedResult)
            }
        } finally {
            $script:screenFile = $oldScreenFile
        }
    }

    Add-Log "No valid duel matchup detail was captured."
    $path = Capture-Screen
    $gift = Invoke-DuelGiftDetect -Path $path
    $remainingGifts = $null
    if ($gift -and $gift.PSObject.Properties.Name -contains "remaining_gifts" -and $null -ne $gift.remaining_gifts) {
        $remainingGifts = [int]$gift.remaining_gifts
    }
    Add-Log "Proceeding with random support using fallback matchup record."
    return (Random-SupportDuelSide -MatchResult (New-FallbackDuelMatchResult -RemainingGifts $remainingGifts))
}

function Test-LoadingScreen {
    param([string]$Path)

    $bitmap = [System.Drawing.Bitmap]::FromFile($Path)
    try {
        $w = $bitmap.Width
        $h = $bitmap.Height
        $step = [Math]::Max(4, [int]($w / 240))
        $samples = 0
        $dark = 0
        $yellowMinX = $w
        $yellowMaxX = 0
        $yellowPixels = 0

        for ($y = 0; $y -lt $h; $y += $step) {
            for ($x = 0; $x -lt $w; $x += $step) {
                $p = $bitmap.GetPixel($x, $y)
                $brightness = ($p.R + $p.G + $p.B) / 3
                if ($brightness -lt 16) {
                    $dark++
                }

                if ($y -gt [int]($h * 0.88) -and $p.R -gt 180 -and $p.G -gt 150 -and $p.B -lt 70) {
                    if ($x -lt $yellowMinX) { $yellowMinX = $x }
                    if ($x -gt $yellowMaxX) { $yellowMaxX = $x }
                    $yellowPixels++
                }

                $samples++
            }
        }

        if (($dark / [Math]::Max(1, $samples)) -gt 0.92) {
            return $true
        }

        $yellowSpan = $yellowMaxX - $yellowMinX
        if ($yellowPixels -gt 20 -and $yellowSpan -gt [int]($w * 0.45)) {
            return $true
        }

        return $false
    } finally {
        $bitmap.Dispose()
    }
}

function Test-HomeScreen {
    param([string]$Path)

    function Get-RegionStats {
        param(
            [System.Drawing.Bitmap]$Bitmap,
            [double]$Left,
            [double]$Top,
            [double]$Right,
            [double]$Bottom,
            [int]$Step
        )

        $w = $Bitmap.Width
        $h = $Bitmap.Height
        $samples = 0
        $bright = 0
        $darkPanel = 0
        $midGray = 0
        $yellow = 0

        for ($y = [int]($h * $Top); $y -lt [int]($h * $Bottom); $y += $Step) {
            for ($x = [int]($w * $Left); $x -lt [int]($w * $Right); $x += $Step) {
                $p = $Bitmap.GetPixel($x, $y)
                $brightness = ($p.R + $p.G + $p.B) / 3
                if ($brightness -gt 185) {
                    $bright++
                }
                if ($brightness -gt 35 -and $brightness -lt 135) {
                    $darkPanel++
                }
                if ($brightness -gt 70 -and $brightness -lt 175 -and [Math]::Abs($p.R - $p.G) -lt 45 -and [Math]::Abs($p.G - $p.B) -lt 45) {
                    $midGray++
                }
                if ($p.R -gt 190 -and $p.G -gt 150 -and $p.B -lt 90) {
                    $yellow++
                }
                $samples++
            }
        }

        return @{
            Bright = $bright / [Math]::Max(1, $samples)
            DarkPanel = $darkPanel / [Math]::Max(1, $samples)
            MidGray = $midGray / [Math]::Max(1, $samples)
            Yellow = $yellow / [Math]::Max(1, $samples)
        }
    }

    $bitmap = [System.Drawing.Bitmap]::FromFile($Path)
    try {
        $w = $bitmap.Width
        $h = $bitmap.Height
        $step = [Math]::Max(6, [int]($w / 220))

        $resourceBar = Get-RegionStats -Bitmap $bitmap -Left 0.48 -Top 0.02 -Right 0.96 -Bottom 0.16 -Step $step
        $terminalCard = Get-RegionStats -Bitmap $bitmap -Left 0.54 -Top 0.16 -Right 0.88 -Bottom 0.44 -Step $step
        $menuCards = Get-RegionStats -Bitmap $bitmap -Left 0.52 -Top 0.42 -Right 0.96 -Bottom 0.93 -Step $step
        $loginButtonArea = Get-RegionStats -Bitmap $bitmap -Left 0.40 -Top 0.61 -Right 0.60 -Bottom 0.76 -Step $step

        $hasResourceBar = ($resourceBar.Bright -gt 0.06 -and $resourceBar.DarkPanel -gt 0.05)
        $hasTerminalCard = ($terminalCard.DarkPanel -gt 0.26 -and $terminalCard.Bright -gt 0.03)
        $hasMenuCards = ($menuCards.DarkPanel -gt 0.28 -and $menuCards.MidGray -gt 0.16)
        $notLoginWake = -not ($loginButtonArea.MidGray -gt 0.22 -and $loginButtonArea.Bright -gt 0.12)

        return ($hasResourceBar -and $hasTerminalCard -and $hasMenuCards -and $notLoginWake)
    } finally {
        $bitmap.Dispose()
    }
}

function Find-YellowStartButton {
    param([string]$Path)

    $bitmap = [System.Drawing.Bitmap]::FromFile($Path)
    try {
        $w = $bitmap.Width
        $h = $bitmap.Height
        $step = [Math]::Max(3, [int]($w / 420))
        $minX = $w
        $minY = $h
        $maxX = 0
        $maxY = 0
        $count = 0

        for ($y = [int]($h * 0.70); $y -lt [int]($h * 0.96); $y += $step) {
            for ($x = [int]($w * 0.35); $x -lt [int]($w * 0.65); $x += $step) {
                $p = $bitmap.GetPixel($x, $y)
                if ($p.R -gt 170 -and $p.G -gt 135 -and $p.B -lt 90 -and ([Math]::Abs($p.R - $p.G) -lt 90)) {
                    if ($x -lt $minX) { $minX = $x }
                    if ($x -gt $maxX) { $maxX = $x }
                    if ($y -lt $minY) { $minY = $y }
                    if ($y -gt $maxY) { $maxY = $y }
                    $count++
                }
            }
        }

        $boxW = $maxX - $minX
        $boxH = $maxY - $minY
        if ($count -gt 20 -and $boxW -gt [int]($w * 0.03) -and $boxW -lt [int]($w * 0.18) -and $boxH -gt [int]($h * 0.04) -and $boxH -lt [int]($h * 0.18)) {
            return @{
                X = [int](($minX + $maxX) / 2)
                Y = [int](($minY + $maxY) / 2)
                W = $boxW
                H = $boxH
            }
        }

        return $null
    } finally {
        $bitmap.Dispose()
    }
}

function Find-StartWakeTextButton {
    param([string]$Path)

    $bitmap = [System.Drawing.Bitmap]::FromFile($Path)
    try {
        $w = $bitmap.Width
        $h = $bitmap.Height
        $step = [Math]::Max(4, [int]($w / 420))
        $grayCount = 0
        $whiteCount = 0

        $roiLeft = [int]($w * 0.40)
        $roiRight = [int]($w * 0.60)
        $roiTop = [int]($h * 0.61)
        $roiBottom = [int]($h * 0.76)

        for ($y = $roiTop; $y -lt $roiBottom; $y += $step) {
            for ($x = $roiLeft; $x -lt $roiRight; $x += $step) {
                $p = $bitmap.GetPixel($x, $y)
                $brightness = ($p.R + $p.G + $p.B) / 3
                $isGrayButton = ($brightness -gt 55 -and $brightness -lt 155 -and [Math]::Abs($p.R - $p.G) -lt 32 -and [Math]::Abs($p.G - $p.B) -lt 32)
                $isWhiteText = ($p.R -gt 175 -and $p.G -gt 175 -and $p.B -gt 175)

                if ($isGrayButton) {
                    $grayCount++
                }
                if ($isWhiteText) {
                    $whiteCount++
                }
            }
        }

        if ($grayCount -lt 180 -or $whiteCount -lt 80) {
            return $null
        }

        return @{
            X = [int]($w * 0.50)
            Y = [int]($h * 0.71)
            W = $roiRight - $roiLeft
            H = $roiBottom - $roiTop
        }
    } finally {
        $bitmap.Dispose()
    }
}

function Auto-ContinueLogin {
    Add-Log "Auto login assist started."
    Wait-AdbReady
    Wait-ArknightsForeground

    $startClicked = $false
    $wakeTapped = $false

    for ($i = 0; $i -lt 36; $i++) {
        Test-StopRequested
        $path = Capture-Screen
        $vision = Invoke-VisionDetect -Path $path
        $state = [string]$vision.state
        $confidence = 0.0
        if ($vision.PSObject.Properties.Name -contains "confidence") {
            $confidence = [double]$vision.confidence
        }
        $method = "visual"
        if ($vision.PSObject.Properties.Name -contains "method") {
            $method = [string]$vision.method
        }
        $text = ""
        if ($vision.PSObject.Properties.Name -contains "text" -and $vision.text) {
            $text = ", text '$($vision.text)'"
        }
        Add-Log ("Vision: {0}, confidence {1:N2}, method {2}{3}." -f $state, $confidence, $method, $text)

        if ($vision.PSObject.Properties.Name -contains "ocr" -and -not [bool]$vision.ocr -and $vision.PSObject.Properties.Name -contains "ocr_error" -and $vision.ocr_error) {
            Add-Log ("OCR unavailable: " + $vision.ocr_error)
        }

        if ($state -eq "loading") {
            Add-Log "Loading screen detected; waiting."
        } elseif ($state -eq "home") {
            Add-Log "Home screen detected; login assist complete."
            return
        } elseif ($state -eq "duel_channel" -or $state -eq "duel_event_select") {
            Add-Log "Duel page detected; login assist complete."
            return
        } elseif ($state -eq "announcement") {
            Close-BlockingOverlay -Vision $vision
        } elseif ($state -eq "start" -and $vision.PSObject.Properties.Name -contains "x" -and $vision.PSObject.Properties.Name -contains "y") {
            if ($startClicked) {
                Add-Log "START already clicked; waiting for next screen."
            } else {
                Add-Log ("START button recognized at {0},{1}." -f $vision.x, $vision.y)
                Tap-Screen -X ([int]$vision.x) -Y ([int]$vision.y) -Reason "vision START"
                $startClicked = $true
            }
        } elseif ($state -eq "wake" -and $vision.PSObject.Properties.Name -contains "x" -and $vision.PSObject.Properties.Name -contains "y") {
            $size = Get-DeviceSize
            $wakeX = [int]($size.Width * 0.50)
            $wakeY = [int]($size.Height * 0.70)
            if ($wakeTapped) {
                Add-Log ("Start Wake still detected; tapping again at {0},{1}." -f $wakeX, $wakeY)
            } else {
                Add-Log ("Start Wake button recognized; tapping at {0},{1}." -f $wakeX, $wakeY)
            }
            Tap-ScreenBurst -X $wakeX -Y $wakeY -Reason "vision Start Wake"
            $wakeTapped = $true
        } elseif ($wakeTapped) {
            Add-Log "Unknown screen after Start Wake; trying to close possible overlay."
            Close-BlockingOverlay -Vision $vision
        } else {
            Add-Log "Target text/button not recognized; waiting."
        }

        Wait-TaskInterval -Seconds $screenIntervalSeconds
    }

    if ($wakeTapped) {
        Add-Log "Wake button tapped, but home screen was not confirmed."
    } else {
        Add-Log "Auto login assist finished without finding wake screen."
    }
}

function Auto-JoinDuelEvent {
    param([int]$LoopLimit = 0)

    if ($LoopLimit -gt 0) {
        Add-Log ("Duel event assist started, loop limit {0}." -f $LoopLimit)
    } else {
        Add-Log "Duel event assist started in continuous mode."
    }
    Wait-AdbReady
    Wait-ArknightsForeground

    $completedRounds = 0
    $duelChannelTapped = $false
    $joinEventTapped = $false
    $casualTapped = $false
    $startGameTapped = $false
    $size = Get-DeviceSize
    $duelX = [int]($size.Width * 0.91)
    $duelY = [int]($size.Height * 0.21)

    while ($true) {
        Test-StopRequested
        $path = Capture-Screen
        $vision = Invoke-VisionDetect -Path $path
        $state = [string]$vision.state
        $confidence = 0.0
        if ($vision.PSObject.Properties.Name -contains "confidence") {
            $confidence = [double]$vision.confidence
        }
        $method = "visual"
        if ($vision.PSObject.Properties.Name -contains "method") {
            $method = [string]$vision.method
        }
        $text = ""
        if ($vision.PSObject.Properties.Name -contains "text" -and $vision.text) {
            $proof = ([string]$vision.text).Replace("`r", " ").Replace("`n", " ")
            if ($proof.Length -gt 80) {
                $proof = $proof.Substring(0, 80) + "..."
            }
            $text = ", text '$proof'"
        }
        Add-Log ("Duel vision: {0}, confidence {1:N2}, method {2}{3}." -f $state, $confidence, $method, $text)

        if ($state -eq "duel_game") {
            Add-Log "Duel game screen detected."
            $roundResult = Collect-DuelMatchInfo
            $completedRounds++
            Add-Log ("Duel matchup and result recorded; completed round {0}." -f $completedRounds)
            if ($LoopLimit -gt 0 -and $completedRounds -ge $LoopLimit) {
                Add-Log ("Loop limit reached: {0} round(s)." -f $LoopLimit)
                return
            }
            $roundSummary = @($roundResult | Where-Object { $_ -and $_.PSObject.Properties.Name -contains "SawFinalSettlement" } | Select-Object -Last 1)
            if ($roundSummary.Count -gt 0 -and [bool]$roundSummary[0].SawFinalSettlement) {
                $duelChannelTapped = $false
                $joinEventTapped = $false
                $casualTapped = $false
                Add-Log "Final settlement handled for this round; resuming duel navigation."
            } else {
                Add-Log "Waiting for next duel round or final settlement page."
            }
            $startGameTapped = $false
            Wait-TaskInterval -Seconds 2
            continue
        } elseif ($state -eq "duel_result" -and $confidence -ge 0.95) {
            Add-Log "Final settlement page still visible after result handling; returning home."
            Return-DuelHomeAfterResult
            $duelChannelTapped = $false
            $joinEventTapped = $false
            $casualTapped = $false
            $startGameTapped = $false
        } elseif ($state -eq "duel_result") {
            Add-Log "Low-confidence final settlement page still visible; checking OCR before returning."
            Return-DuelHomeAfterResult
            $duelChannelTapped = $false
            $joinEventTapped = $false
            $casualTapped = $false
            $startGameTapped = $false
        } elseif ($state -eq "start") {
            $finalGift = Invoke-DuelFinalGiftDetect -Path $path
            if (Test-DuelFinalGiftEvidence -FinalGift $finalGift) {
                Add-Log "Final settlement page misdetected as START; returning home."
                Return-DuelHomeAfterResult
                $duelChannelTapped = $false
                $joinEventTapped = $false
                $casualTapped = $false
                $startGameTapped = $false
            } else {
                Add-Log "Duel target not recognized; waiting."
            }
        } elseif ($state -eq "duel_casual_selected" -and $vision.PSObject.Properties.Name -contains "x" -and $vision.PSObject.Properties.Name -contains "y") {
            if ($startGameTapped) {
                Add-Log "Start Game already clicked; waiting for duel game screen."
            } else {
                Add-Log ("Casual mode selected; tapping Start Game at {0},{1}." -f $vision.x, $vision.y)
                Tap-Screen -X ([int]$vision.x) -Y ([int]$vision.y) -Reason "vision Start Game"
                $startGameTapped = $true
            }
        } elseif ($state -eq "duel_event_select" -and $vision.PSObject.Properties.Name -contains "x" -and $vision.PSObject.Properties.Name -contains "y") {
            if ($casualTapped) {
                Add-Log "Casual mode already clicked; waiting for Start Game screen."
            } else {
                Add-Log ("Event selection detected; tapping Casual mode at {0},{1}." -f $vision.x, $vision.y)
                Tap-Screen -X ([int]$vision.x) -Y ([int]$vision.y) -Reason "vision Casual Mode"
                $casualTapped = $true
            }
        } elseif ($state -eq "duel_channel" -and $vision.PSObject.Properties.Name -contains "x" -and $vision.PSObject.Properties.Name -contains "y") {
            if ($joinEventTapped) {
                Add-Log "Join Event already clicked; waiting for event selection screen."
            } else {
                Add-Log ("Join Event button recognized at {0},{1}." -f $vision.x, $vision.y)
                Tap-Screen -X ([int]$vision.x) -Y ([int]$vision.y) -Reason "vision Join Event"
                $joinEventTapped = $true
            }
        } elseif ($state -eq "home") {
            $finalGift = Invoke-DuelFinalGiftDetect -Path $path
            if (Test-DuelFinalGiftEvidence -FinalGift $finalGift) {
                Add-Log "Final settlement page misdetected as home; returning home."
                Return-DuelHomeAfterResult
                $duelChannelTapped = $false
                $joinEventTapped = $false
                $casualTapped = $false
                $startGameTapped = $false
            } else {
                if ($duelChannelTapped) {
                    Add-Log "Duel Channel already clicked; waiting for channel page."
                } else {
                    Add-Log ("Home detected; tapping Duel Channel at {0},{1}." -f $duelX, $duelY)
                    Tap-Screen -X $duelX -Y $duelY -Reason "Duel Channel"
                    $duelChannelTapped = $true
                }
            }
        } elseif ($state -eq "loading") {
            Add-Log "Loading screen detected; waiting."
        } else {
            Add-Log "Duel target not recognized; waiting."
        }

        Wait-TaskInterval -Seconds $screenIntervalSeconds
    }
}

function Start-Arknights {
    if (-not (Test-Path -LiteralPath $manager)) {
        throw "MuMuManager.exe not found: $manager"
    }

    if (-not (Test-Path -LiteralPath $main)) {
        throw "MuMuNxMain.exe not found: $main"
    }

    $info = Get-MuMuInfo
    $isStarted = $false
    if ($info -and $info.PSObject.Properties.Name -contains "is_process_started") {
        $isStarted = [bool]$info.is_process_started
    }

    if ($isStarted) {
        Add-Log "MuMu is already open. Launching Arknights app."
        $code = Invoke-MuMu -Arguments @("control", "--vmindex", "$VmIndex", "app", "launch", "--package", $Package)
        if ($code -eq 0) {
            return
        }

        Add-Log "App launch failed; trying combined launch command."
    } else {
        Add-Log "MuMu is closed. Starting MuMu with Arknights."
    }

    $code = Invoke-MuMu -Arguments @("control", "--vmindex", "$VmIndex", "launch", "--package", $Package)
    if ($code -ne 0) {
        throw "MuMu launch command failed."
    }
}

. (Join-Path $appRoot "Launcher.UI.ps1")

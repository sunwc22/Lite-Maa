Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$accent = [System.Drawing.Color]::FromArgb(170, 0, 160)
$accentDark = [System.Drawing.Color]::FromArgb(72, 24, 150)
$accentSoft = [System.Drawing.Color]::FromArgb(248, 232, 249)
$appBg = [System.Drawing.Color]::FromArgb(246, 243, 249)
$cardBg = [System.Drawing.Color]::White
$mutedText = [System.Drawing.Color]::FromArgb(108, 101, 122)
$border = [System.Drawing.Color]::FromArgb(226, 216, 234)

function Set-ModernButton {
    param(
        [System.Windows.Forms.Button]$Button,
        [System.Drawing.Color]$BackColor,
        [System.Drawing.Color]$ForeColor,
        [bool]$Bold = $true
    )
    $Button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $Button.FlatAppearance.BorderSize = 0
    $Button.BackColor = $BackColor
    $Button.ForeColor = $ForeColor
    if ($Bold) {
        $Button.Font = New-Object System.Drawing.Font -ArgumentList "Microsoft YaHei UI", 10.5, ([System.Drawing.FontStyle]::Bold)
    } else {
        $Button.Font = New-Object System.Drawing.Font -ArgumentList "Microsoft YaHei UI", 9.5
    }
    $Button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $Button.UseVisualStyleBackColor = $false
}

function Set-CardStyle {
    param([System.Windows.Forms.Control]$Control)
    $Control.BackColor = [System.Drawing.Color]::White
    $Control.Padding = New-Object System.Windows.Forms.Padding -ArgumentList 8
}



$form = New-Object System.Windows.Forms.Form
$form.Text = "LauncherX - Arknights MuMu Automation"
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.Size = New-Object System.Drawing.Size -ArgumentList 1080, 720
$form.MinimumSize = New-Object System.Drawing.Size -ArgumentList 940, 620
$form.Font = New-Object System.Drawing.Font -ArgumentList "Microsoft YaHei UI", 9
$form.BackColor = $appBg


function New-TaskRow {
    param(
        [System.Windows.Forms.Control]$Parent,
        [string]$Text,
        [int]$Y,
        [bool]$Checked,
        [bool]$HasSettings
    )

    $check = New-Object System.Windows.Forms.CheckBox
    $check.Text = $Text
    $check.Checked = $Checked
    $check.Location = New-Object System.Drawing.Point -ArgumentList 24, $Y
    $check.Size = New-Object System.Drawing.Size -ArgumentList 190, 30
    $check.Font = New-Object System.Drawing.Font -ArgumentList "Microsoft YaHei UI", 10
    $check.ForeColor = [System.Drawing.Color]::FromArgb(35, 35, 35)
    $Parent.Controls.Add($check)

    $gear = New-Object System.Windows.Forms.Button
    $gear.Text = "设置"
    $gear.Enabled = $HasSettings
    $gear.Location = New-Object System.Drawing.Point -ArgumentList 246, ($Y + 2)
    $gear.Size = New-Object System.Drawing.Size -ArgumentList 34, 26
    $gear.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $gear.FlatAppearance.BorderColor = $border
    $gear.BackColor = [System.Drawing.Color]::White
    $gear.ForeColor = $accent
    $gear.Cursor = [System.Windows.Forms.Cursors]::Hand
    $Parent.Controls.Add($gear)

    return [pscustomobject]@{
        CheckBox = $check
        SettingsButton = $gear
    }
}

$rootLayout = New-Object System.Windows.Forms.TableLayoutPanel
$rootLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
$rootLayout.RowCount = 2
$rootLayout.ColumnCount = 1
$rootLayout.BackColor = $appBg
$rootLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 170))) | Out-Null
$rootLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
$form.Controls.Add($rootLayout)

$heroPanel = New-Object System.Windows.Forms.Panel
$heroPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$heroPanel.BackColor = $accentDark
$heroPanel.Add_Paint({
    param($sender, $e)
    $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $rect = New-Object System.Drawing.Rectangle -ArgumentList 0, 0, $sender.Width, $sender.Height
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $accentDark, [System.Drawing.Color]::FromArgb(220, 0, 160), 18)
    $e.Graphics.FillRectangle($brush, $rect)
    $brush.Dispose()

    $penA = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(90, 255, 180, 245), 2)
    $penB = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(46, 255, 255, 255), 1)
    $e.Graphics.DrawBezier($penA, -80, 145, 150, -45, 340, -20, 560, 120)
    $e.Graphics.DrawBezier($penA, -30, 42, 170, 78, 350, 24, 520, 60)
    $e.Graphics.DrawBezier($penB, 630, 190, 720, 105, 900, 155, 1120, 44)
    $penA.Dispose()
    $penB.Dispose()
})
$rootLayout.Controls.Add($heroPanel, 0, 0)

$brandLabel = New-Object System.Windows.Forms.Label
$brandLabel.Text = "✦ LauncherX"
$brandLabel.Font = New-Object System.Drawing.Font -ArgumentList "Microsoft YaHei UI", 18, ([System.Drawing.FontStyle]::Bold)
$brandLabel.ForeColor = [System.Drawing.Color]::White
$brandLabel.BackColor = [System.Drawing.Color]::Transparent
$brandLabel.Location = New-Object System.Drawing.Point -ArgumentList 40, 24
$brandLabel.Size = New-Object System.Drawing.Size -ArgumentList 260, 38
$heroPanel.Controls.Add($brandLabel)

$heroTitle = New-Object System.Windows.Forms.Label
$heroTitle.Text = "Arknights MuMu Automation"
$heroTitle.Font = New-Object System.Drawing.Font -ArgumentList "Microsoft YaHei UI", 24, ([System.Drawing.FontStyle]::Bold)
$heroTitle.ForeColor = [System.Drawing.Color]::White
$heroTitle.BackColor = [System.Drawing.Color]::Transparent
$heroTitle.Location = New-Object System.Drawing.Point -ArgumentList 44, 86
$heroTitle.Size = New-Object System.Drawing.Size -ArgumentList 620, 46
$heroPanel.Controls.Add($heroTitle)

$heroSub = New-Object System.Windows.Forms.Label
$heroSub.Text = "启动、登录、Duel Channel 自动化 · 稳定执行 · 可随时停止"
$heroSub.Font = New-Object System.Drawing.Font -ArgumentList "Microsoft YaHei UI", 10.5
$heroSub.ForeColor = [System.Drawing.Color]::FromArgb(238, 231, 246)
$heroSub.BackColor = [System.Drawing.Color]::Transparent
$heroSub.Location = New-Object System.Drawing.Point -ArgumentList 48, 132
$heroSub.Size = New-Object System.Drawing.Size -ArgumentList 620, 24
$heroPanel.Controls.Add($heroSub)

$statusPill = New-Object System.Windows.Forms.Label
$statusPill.Text = "● 当前有1个任务正在运行"
$statusPill.Font = New-Object System.Drawing.Font -ArgumentList "Microsoft YaHei UI", 9.5, ([System.Drawing.FontStyle]::Bold)
$statusPill.ForeColor = [System.Drawing.Color]::White
$statusPill.BackColor = [System.Drawing.Color]::FromArgb(120, 255, 255, 255)
$statusPill.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$statusPill.Location = New-Object System.Drawing.Point -ArgumentList 760, 30
$statusPill.Size = New-Object System.Drawing.Size -ArgumentList 208, 34
$statusPill.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$heroPanel.Controls.Add($statusPill)

$heroControls = New-Object System.Windows.Forms.Label
$heroControls.Text = "⚙  ☺    —   □   ✕"
$heroControls.Font = New-Object System.Drawing.Font -ArgumentList "Microsoft YaHei UI", 15
$heroControls.ForeColor = [System.Drawing.Color]::White
$heroControls.BackColor = [System.Drawing.Color]::Transparent
$heroControls.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$heroControls.Location = New-Object System.Drawing.Point -ArgumentList 950, 28
$heroControls.Size = New-Object System.Drawing.Size -ArgumentList 110, 36
$heroControls.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$heroPanel.Controls.Add($heroControls)

$profileCard = New-Object System.Windows.Forms.Panel
$profileCard.Location = New-Object System.Drawing.Point -ArgumentList 760, 90
$profileCard.Size = New-Object System.Drawing.Size -ArgumentList 270, 64
$profileCard.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$profileCard.BackColor = [System.Drawing.Color]::FromArgb(118, 255, 255, 255)
$heroPanel.Controls.Add($profileCard)

$profileAvatar = New-Object System.Windows.Forms.Label
$profileAvatar.Text = "■"
$profileAvatar.Font = New-Object System.Drawing.Font -ArgumentList "Microsoft YaHei UI", 34, ([System.Drawing.FontStyle]::Bold)
$profileAvatar.ForeColor = [System.Drawing.Color]::FromArgb(68, 184, 78)
$profileAvatar.BackColor = [System.Drawing.Color]::Transparent
$profileAvatar.Location = New-Object System.Drawing.Point -ArgumentList 14, 8
$profileAvatar.Size = New-Object System.Drawing.Size -ArgumentList 44, 48
$profileCard.Controls.Add($profileAvatar)

$profileName = New-Object System.Windows.Forms.Label
$profileName.Text = "WanZiDuan"
$profileName.Font = New-Object System.Drawing.Font -ArgumentList "Microsoft YaHei UI", 12, ([System.Drawing.FontStyle]::Bold)
$profileName.ForeColor = [System.Drawing.Color]::White
$profileName.BackColor = [System.Drawing.Color]::Transparent
$profileName.Location = New-Object System.Drawing.Point -ArgumentList 70, 12
$profileName.Size = New-Object System.Drawing.Size -ArgumentList 160, 24
$profileCard.Controls.Add($profileName)

$profileSub = New-Object System.Windows.Forms.Label
$profileSub.Text = "本地自动化配置"
$profileSub.Font = New-Object System.Drawing.Font -ArgumentList "Microsoft YaHei UI", 9
$profileSub.ForeColor = [System.Drawing.Color]::FromArgb(238, 231, 246)
$profileSub.BackColor = [System.Drawing.Color]::Transparent
$profileSub.Location = New-Object System.Drawing.Point -ArgumentList 70, 36
$profileSub.Size = New-Object System.Drawing.Size -ArgumentList 160, 20
$profileCard.Controls.Add($profileSub)


$contentLayout = New-Object System.Windows.Forms.TableLayoutPanel
$contentLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
$contentLayout.ColumnCount = 2
$contentLayout.RowCount = 1
$contentLayout.Padding = New-Object System.Windows.Forms.Padding -ArgumentList 34, 24, 30, 28
$contentLayout.BackColor = $appBg
$contentLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
$contentLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 380))) | Out-Null
$rootLayout.Controls.Add($contentLayout, 0, 1)

$taskPanel = New-Object System.Windows.Forms.Panel
$taskPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$taskPanel.BackColor = $appBg
$contentLayout.Controls.Add($taskPanel, 0, 0)

$taskBottomPanel = New-Object System.Windows.Forms.Panel
$taskBottomPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
$taskBottomPanel.Height = 174
$taskBottomPanel.BackColor = $cardBg
$taskPanel.Controls.Add($taskBottomPanel)
Set-CardStyle $taskBottomPanel

$taskCard = New-Object System.Windows.Forms.Panel
$taskCard.Dock = [System.Windows.Forms.DockStyle]::Top
$taskCard.Height = 166
$taskCard.Padding = New-Object System.Windows.Forms.Padding -ArgumentList 8
$taskCard.BackColor = $cardBg
$taskPanel.Controls.Add($taskCard)
Set-CardStyle $taskCard

$taskTitle = New-Object System.Windows.Forms.Label
$taskTitle.Text = "自动任务"
$taskTitle.Font = New-Object System.Drawing.Font -ArgumentList "Microsoft YaHei UI", 13, ([System.Drawing.FontStyle]::Bold)
$taskTitle.ForeColor = [System.Drawing.Color]::FromArgb(32, 28, 42)
$taskTitle.Location = New-Object System.Drawing.Point -ArgumentList 24, 16
$taskTitle.Size = New-Object System.Drawing.Size -ArgumentList 160, 28
$taskCard.Controls.Add($taskTitle)

$taskHint = New-Object System.Windows.Forms.Label
$taskHint.Text = "选择流程，点击设置可切换对应参数。"
$taskHint.Font = New-Object System.Drawing.Font -ArgumentList "Microsoft YaHei UI", 9
$taskHint.ForeColor = $mutedText
$taskHint.Location = New-Object System.Drawing.Point -ArgumentList 150, 20
$taskHint.Size = New-Object System.Drawing.Size -ArgumentList 300, 22
$taskCard.Controls.Add($taskHint)

$startWakeRow = New-TaskRow -Parent $taskCard -Text "启动唤醒 / Start Wake" -Y 58 -Checked $true -HasSettings $true
$joinDuelRow = New-TaskRow -Parent $taskCard -Text "加入 Duel 活动" -Y 104 -Checked $true -HasSettings $true
$startWakeCheckBox = $startWakeRow.CheckBox
$joinDuelCheckBox = $joinDuelRow.CheckBox

$afterLabel = New-Object System.Windows.Forms.Label
$afterLabel.Text = "完成后"
$afterLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$afterLabel.Location = New-Object System.Drawing.Point -ArgumentList 52, 12
$afterLabel.Size = New-Object System.Drawing.Size -ArgumentList 190, 24
$taskBottomPanel.Controls.Add($afterLabel)

$afterComboBox = New-Object System.Windows.Forms.ComboBox
$afterComboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$afterComboBox.Items.AddRange([object[]]@("不执行操作", "关闭游戏", "关闭模拟器"))
$afterComboBox.SelectedIndex = 0
$afterComboBox.Location = New-Object System.Drawing.Point -ArgumentList 52, 40
$afterComboBox.Size = New-Object System.Drawing.Size -ArgumentList 190, 26
$taskBottomPanel.Controls.Add($afterComboBox)

$launchButton = New-Object System.Windows.Forms.Button
$launchButton.Text = "▶ 开始执行"
$launchButton.Location = New-Object System.Drawing.Point -ArgumentList 42, 92
$launchButton.Size = New-Object System.Drawing.Size -ArgumentList 130, 48
$taskBottomPanel.Controls.Add($launchButton)

$stopButton = New-Object System.Windows.Forms.Button
$stopButton.Text = "停止"
$stopButton.Enabled = $false
$stopButton.Location = New-Object System.Drawing.Point -ArgumentList 164, 92
$stopButton.Size = New-Object System.Drawing.Size -ArgumentList 90, 48
$taskBottomPanel.Controls.Add($stopButton)
Set-ModernButton -Button $launchButton -BackColor $accent -ForeColor ([System.Drawing.Color]::White)
Set-ModernButton -Button $stopButton -BackColor $accentSoft -ForeColor $accent

$settingsPanel = New-Object System.Windows.Forms.Panel
$settingsPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$settingsPanel.BackColor = $cardBg
$taskPanel.Controls.Add($settingsPanel)
Set-CardStyle $settingsPanel
$taskCard.BringToFront()
$taskBottomPanel.BringToFront()

$settingsTitle = New-Object System.Windows.Forms.Label
$settingsTitle.Text = "Start Wake"
$settingsTitle.Font = New-Object System.Drawing.Font -ArgumentList "Microsoft YaHei UI", 16, ([System.Drawing.FontStyle]::Bold)
$settingsTitle.Location = New-Object System.Drawing.Point -ArgumentList 24, 18
$settingsTitle.Size = New-Object System.Drawing.Size -ArgumentList 360, 36
$settingsPanel.Controls.Add($settingsTitle)

$settingsNote = New-Object System.Windows.Forms.Label
$settingsNote.Text = "Launch MuMu, continue login, then open Duel Channel and enter Join Event when enabled."
$settingsNote.ForeColor = $mutedText
$settingsNote.Location = New-Object System.Drawing.Point -ArgumentList 26, 58
$settingsNote.Size = New-Object System.Drawing.Size -ArgumentList 430, 24
$settingsPanel.Controls.Add($settingsNote)

$autoLoginCheckBox = New-Object System.Windows.Forms.CheckBox
$autoLoginCheckBox.Text = "启动后自动继续登录"
$autoLoginCheckBox.Checked = $true
$autoLoginCheckBox.Location = New-Object System.Drawing.Point -ArgumentList 24, 110
$autoLoginCheckBox.Size = New-Object System.Drawing.Size -ArgumentList 260, 26
$settingsPanel.Controls.Add($autoLoginCheckBox)

$duelLoopLabel = New-Object System.Windows.Forms.Label
$duelLoopLabel.Text = "循环次数"
$duelLoopLabel.Location = New-Object System.Drawing.Point -ArgumentList 24, 110
$duelLoopLabel.Size = New-Object System.Drawing.Size -ArgumentList 110, 24
$duelLoopLabel.Visible = $false
$settingsPanel.Controls.Add($duelLoopLabel)

$duelLoopUpDown = New-Object System.Windows.Forms.NumericUpDown
$duelLoopUpDown.Minimum = 0
$duelLoopUpDown.Maximum = 999
$duelLoopUpDown.Value = 0
$duelLoopUpDown.Location = New-Object System.Drawing.Point -ArgumentList 136, 108
$duelLoopUpDown.Size = New-Object System.Drawing.Size -ArgumentList 90, 24
$duelLoopUpDown.Visible = $false
$settingsPanel.Controls.Add($duelLoopUpDown)

$duelLoopHint = New-Object System.Windows.Forms.Label
$duelLoopHint.Text = "0 means unlimited. Each loop records one matchup and winner, returns to Duel Channel, then starts the next game."
$duelLoopHint.ForeColor = $mutedText
$duelLoopHint.Location = New-Object System.Drawing.Point -ArgumentList 24, 146
$duelLoopHint.Size = New-Object System.Drawing.Size -ArgumentList 412, 54
$duelLoopHint.Visible = $false
$settingsPanel.Controls.Add($duelLoopHint)

$pathLabel = New-Object System.Windows.Forms.Label
$pathLabel.Text = "MuMu 根目录"
$pathLabel.Location = New-Object System.Drawing.Point -ArgumentList 24, 166
$pathLabel.Size = New-Object System.Drawing.Size -ArgumentList 110, 24
$settingsPanel.Controls.Add($pathLabel)

$pathText = New-Object System.Windows.Forms.TextBox
$pathText.Text = $MuMuRoot
$pathText.ReadOnly = $true
$pathText.Location = New-Object System.Drawing.Point -ArgumentList 136, 164
$pathText.Size = New-Object System.Drawing.Size -ArgumentList 300, 24
$pathText.Anchor = [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$settingsPanel.Controls.Add($pathText)

$vmLabel = New-Object System.Windows.Forms.Label
$vmLabel.Text = "模拟器实例"
$vmLabel.Location = New-Object System.Drawing.Point -ArgumentList 24, 210
$vmLabel.Size = New-Object System.Drawing.Size -ArgumentList 110, 24
$settingsPanel.Controls.Add($vmLabel)

$vmText = New-Object System.Windows.Forms.NumericUpDown
$vmText.Value = $VmIndex
$vmText.Minimum = 0
$vmText.Maximum = 9
$vmText.Enabled = $false
$vmText.Location = New-Object System.Drawing.Point -ArgumentList 136, 208
$vmText.Size = New-Object System.Drawing.Size -ArgumentList 120, 24
$settingsPanel.Controls.Add($vmText)

$packageLabel = New-Object System.Windows.Forms.Label
$packageLabel.Text = "游戏包名"
$packageLabel.Location = New-Object System.Drawing.Point -ArgumentList 24, 254
$packageLabel.Size = New-Object System.Drawing.Size -ArgumentList 110, 24
$settingsPanel.Controls.Add($packageLabel)

$packageText = New-Object System.Windows.Forms.TextBox
$packageText.Text = $Package
$packageText.ReadOnly = $true
$packageText.Location = New-Object System.Drawing.Point -ArgumentList 136, 252
$packageText.Size = New-Object System.Drawing.Size -ArgumentList 300, 24
$packageText.Anchor = [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$settingsPanel.Controls.Add($packageText)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point -ArgumentList 24, 326
$progressBar.Size = New-Object System.Drawing.Size -ArgumentList 412, 12
$progressBar.Anchor = [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Blocks
$settingsPanel.Controls.Add($progressBar)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Ready"
$statusLabel.ForeColor = $mutedText
$statusLabel.Location = New-Object System.Drawing.Point -ArgumentList 24, 350
$statusLabel.Size = New-Object System.Drawing.Size -ArgumentList 412, 26
$settingsPanel.Controls.Add($statusLabel)

$tipGroup = New-Object System.Windows.Forms.GroupBox
$tipGroup.Text = "Tips"
$tipGroup.Location = New-Object System.Drawing.Point -ArgumentList 24, 420
$tipGroup.Size = New-Object System.Drawing.Size -ArgumentList 412, 130
$tipGroup.Anchor = [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$settingsPanel.Controls.Add($tipGroup)

$tipLabel = New-Object System.Windows.Forms.Label
$tipLabel.Text = "The helper uses MuMu enhanced screenshots and internal vision detection. It opens Duel Channel from home, joins the event page, and stops at event selection."
$tipLabel.Location = New-Object System.Drawing.Point -ArgumentList 18, 32
$tipLabel.Size = New-Object System.Drawing.Size -ArgumentList 370, 80
$tipGroup.Controls.Add($tipLabel)

function Show-StartWakeSettings {
    $settingsTitle.Text = "Start Wake"
    $settingsNote.Text = "Launch MuMu and continue login until the Arknights home screen."
    $autoLoginCheckBox.Visible = $true
    $duelLoopLabel.Visible = $false
    $duelLoopUpDown.Visible = $false
    $duelLoopHint.Visible = $false
    $pathLabel.Visible = $true
    $pathText.Visible = $true
    $vmLabel.Visible = $true
    $vmText.Visible = $true
    $packageLabel.Visible = $true
    $packageText.Visible = $true
    $tipLabel.Text = "Start Wake opens Arknights, handles START/Start Wake screens, closes blocking popups, and stops at the home page."
}

function Show-JoinDuelSettings {
    $settingsTitle.Text = "Join Duel Event"
    $settingsNote.Text = "Run Duel Channel automation and repeat for the selected number of completed games."
    $autoLoginCheckBox.Visible = $false
    $duelLoopLabel.Visible = $true
    $duelLoopUpDown.Visible = $true
    $duelLoopHint.Visible = $true
    $pathLabel.Visible = $false
    $pathText.Visible = $false
    $vmLabel.Visible = $false
    $vmText.Visible = $false
    $packageLabel.Visible = $false
    $packageText.Visible = $false
    $tipLabel.Text = "After each duel result is recorded, the helper taps Return Home and starts the next game. Set 0 for unlimited loops."
}

$startWakeRow.SettingsButton.Add_Click({
    Show-StartWakeSettings
})

$joinDuelRow.SettingsButton.Add_Click({
    Show-JoinDuelSettings
})

$logPanel = New-Object System.Windows.Forms.Panel
$logPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$logPanel.Padding = New-Object System.Windows.Forms.Padding -ArgumentList 10
$logPanel.BackColor = $cardBg
$contentLayout.Controls.Add($logPanel, 1, 0)
Set-CardStyle $logPanel

$logTitle = New-Object System.Windows.Forms.Label
$logTitle.Text = "运行日志"
$logTitle.Dock = [System.Windows.Forms.DockStyle]::Top
$logTitle.Height = 28
$logTitle.Font = New-Object System.Drawing.Font -ArgumentList "Microsoft YaHei UI", 12, ([System.Drawing.FontStyle]::Bold)
$logPanel.Controls.Add($logTitle)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Dock = [System.Windows.Forms.DockStyle]::Fill
$logBox.Multiline = $true
$logBox.ReadOnly = $true
$logBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$logBox.Font = New-Object System.Drawing.Font -ArgumentList "Consolas", 9
$logBox.BackColor = [System.Drawing.Color]::FromArgb(37, 30, 48)
$logBox.ForeColor = [System.Drawing.Color]::FromArgb(235, 229, 242)
$logBox.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$logPanel.Controls.Add($logBox)

$form.Add_Shown({
    Add-Log "Ready."
})

$stopButton.Add_Click({
    $script:stopRequested = $true
    $stopButton.Enabled = $false
    $statusLabel.Text = "Stopping..."
    Add-Log "Stop requested."
})

$launchButton.Add_Click({
    $script:stopRequested = $false
    Set-Busy $true
    Add-Log "Launching..."

    try {
        if ($startWakeCheckBox.Checked -or $joinDuelCheckBox.Checked) {
            Start-Arknights
        }

        if ($startWakeCheckBox.Checked -and $autoLoginCheckBox.Checked) {
            Auto-ContinueLogin
        }

        if ($joinDuelCheckBox.Checked) {
            Auto-JoinDuelEvent -LoopLimit ([int]$duelLoopUpDown.Value)
        }
        Add-Log "Done."
        $statusLabel.Text = "Complete"
    } catch {
        Add-Log ("Failed: " + $_.Exception.Message)
        if ($_.Exception.Message -eq "Task stopped by user.") {
            $statusLabel.Text = "Stopped"
        } else {
            $statusLabel.Text = "Failed"
            [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Launch failed", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    } finally {
        Set-Busy $false
    }
})

[System.Windows.Forms.Application]::Run($form)

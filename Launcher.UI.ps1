[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = "MAA Lite - MuMu Emulator (16384) - Official"
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.Size = New-Object System.Drawing.Size -ArgumentList 980, 660
$form.MinimumSize = New-Object System.Drawing.Size -ArgumentList 860, 560
$form.Font = New-Object System.Drawing.Font -ArgumentList "Microsoft YaHei UI", 9
$form.BackColor = [System.Drawing.Color]::White

$accent = [System.Drawing.Color]::FromArgb(170, 0, 160)
$border = [System.Drawing.Color]::FromArgb(220, 220, 220)

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
    $gear.Text = "..."
    $gear.Enabled = $HasSettings
    $gear.Location = New-Object System.Drawing.Point -ArgumentList 246, ($Y + 2)
    $gear.Size = New-Object System.Drawing.Size -ArgumentList 34, 26
    $gear.FlatStyle = [System.Windows.Forms.FlatStyle]::System
    $Parent.Controls.Add($gear)

    return [pscustomobject]@{
        CheckBox = $check
        SettingsButton = $gear
    }
}

$rootLayout = New-Object System.Windows.Forms.TableLayoutPanel
$rootLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
$rootLayout.RowCount = 1
$rootLayout.ColumnCount = 1
$rootLayout.BackColor = [System.Drawing.Color]::White
$rootLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
$form.Controls.Add($rootLayout)

$contentLayout = New-Object System.Windows.Forms.TableLayoutPanel
$contentLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
$contentLayout.ColumnCount = 2
$contentLayout.RowCount = 1
$contentLayout.Padding = New-Object System.Windows.Forms.Padding -ArgumentList 40, 32, 26, 26
$contentLayout.BackColor = [System.Drawing.Color]::White
$contentLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
$contentLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 380))) | Out-Null
$rootLayout.Controls.Add($contentLayout, 0, 0)

$taskPanel = New-Object System.Windows.Forms.Panel
$taskPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$taskPanel.BackColor = [System.Drawing.Color]::White
$contentLayout.Controls.Add($taskPanel, 0, 0)

$taskBottomPanel = New-Object System.Windows.Forms.Panel
$taskBottomPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
$taskBottomPanel.Height = 174
$taskBottomPanel.BackColor = [System.Drawing.Color]::White
$taskPanel.Controls.Add($taskBottomPanel)

$taskCard = New-Object System.Windows.Forms.GroupBox
$taskCard.Text = ""
$taskCard.Dock = [System.Windows.Forms.DockStyle]::Top
$taskCard.Height = 154
$taskCard.Padding = New-Object System.Windows.Forms.Padding -ArgumentList 4
$taskPanel.Controls.Add($taskCard)

$startWakeRow = New-TaskRow -Parent $taskCard -Text "Start Wake" -Y 30 -Checked $true -HasSettings $true
$joinDuelRow = New-TaskRow -Parent $taskCard -Text "Join Duel Event" -Y 72 -Checked $true -HasSettings $true
$startWakeCheckBox = $startWakeRow.CheckBox
$joinDuelCheckBox = $joinDuelRow.CheckBox

$afterLabel = New-Object System.Windows.Forms.Label
$afterLabel.Text = "After complete"
$afterLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$afterLabel.Location = New-Object System.Drawing.Point -ArgumentList 52, 12
$afterLabel.Size = New-Object System.Drawing.Size -ArgumentList 190, 24
$taskBottomPanel.Controls.Add($afterLabel)

$afterComboBox = New-Object System.Windows.Forms.ComboBox
$afterComboBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$afterComboBox.Items.AddRange([object[]]@("Do nothing", "Close game", "Close emulator"))
$afterComboBox.SelectedIndex = 0
$afterComboBox.Location = New-Object System.Drawing.Point -ArgumentList 52, 40
$afterComboBox.Size = New-Object System.Drawing.Size -ArgumentList 190, 26
$taskBottomPanel.Controls.Add($afterComboBox)

$launchButton = New-Object System.Windows.Forms.Button
$launchButton.Text = "Link Start!"
$launchButton.Location = New-Object System.Drawing.Point -ArgumentList 42, 92
$launchButton.Size = New-Object System.Drawing.Size -ArgumentList 110, 48
$taskBottomPanel.Controls.Add($launchButton)

$stopButton = New-Object System.Windows.Forms.Button
$stopButton.Text = "Stop"
$stopButton.Enabled = $false
$stopButton.Location = New-Object System.Drawing.Point -ArgumentList 164, 92
$stopButton.Size = New-Object System.Drawing.Size -ArgumentList 90, 48
$taskBottomPanel.Controls.Add($stopButton)

$settingsPanel = New-Object System.Windows.Forms.Panel
$settingsPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$settingsPanel.BackColor = [System.Drawing.Color]::White
$taskPanel.Controls.Add($settingsPanel)
$taskCard.BringToFront()
$taskBottomPanel.BringToFront()

$settingsTitle = New-Object System.Windows.Forms.Label
$settingsTitle.Text = "Start Wake"
$settingsTitle.Font = New-Object System.Drawing.Font -ArgumentList "Microsoft YaHei UI", 16, ([System.Drawing.FontStyle]::Bold)
$settingsTitle.Location = New-Object System.Drawing.Point -ArgumentList 18, 12
$settingsTitle.Size = New-Object System.Drawing.Size -ArgumentList 360, 36
$settingsPanel.Controls.Add($settingsTitle)

$settingsNote = New-Object System.Windows.Forms.Label
$settingsNote.Text = "Launch MuMu, continue login, then open Duel Channel and enter Join Event when enabled."
$settingsNote.ForeColor = [System.Drawing.Color]::DimGray
$settingsNote.Location = New-Object System.Drawing.Point -ArgumentList 20, 52
$settingsNote.Size = New-Object System.Drawing.Size -ArgumentList 430, 24
$settingsPanel.Controls.Add($settingsNote)

$autoLoginCheckBox = New-Object System.Windows.Forms.CheckBox
$autoLoginCheckBox.Text = "Continue login after launch"
$autoLoginCheckBox.Checked = $true
$autoLoginCheckBox.Location = New-Object System.Drawing.Point -ArgumentList 24, 110
$autoLoginCheckBox.Size = New-Object System.Drawing.Size -ArgumentList 260, 26
$settingsPanel.Controls.Add($autoLoginCheckBox)

$duelLoopLabel = New-Object System.Windows.Forms.Label
$duelLoopLabel.Text = "Loop count"
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
$duelLoopHint.ForeColor = [System.Drawing.Color]::DimGray
$duelLoopHint.Location = New-Object System.Drawing.Point -ArgumentList 24, 146
$duelLoopHint.Size = New-Object System.Drawing.Size -ArgumentList 412, 54
$duelLoopHint.Visible = $false
$settingsPanel.Controls.Add($duelLoopHint)

$pathLabel = New-Object System.Windows.Forms.Label
$pathLabel.Text = "MuMu root"
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
$vmLabel.Text = "Instance"
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
$packageLabel.Text = "Package"
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
$statusLabel.ForeColor = [System.Drawing.Color]::DimGray
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
$logPanel.BackColor = [System.Drawing.Color]::FromArgb(248, 248, 248)
$contentLayout.Controls.Add($logPanel, 1, 0)

$logTitle = New-Object System.Windows.Forms.Label
$logTitle.Text = "Log"
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
$logBox.BackColor = [System.Drawing.Color]::White
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

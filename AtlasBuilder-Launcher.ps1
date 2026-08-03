# Riverheim AtlasBuilder launcher. Run with Windows PowerShell in STA mode.
[CmdletBinding()]
param()

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'
[System.Windows.Forms.Application]::EnableVisualStyles()

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$defaultExe = Join-Path $scriptRoot 'Riverheim.AtlasBuilder.exe'
$defaultOutput = Join-Path ([Environment]::GetFolderPath('MyPictures')) 'Riverheim Maps'

function New-Label {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width = 105)
    $label = [System.Windows.Forms.Label]::new()
    $label.Text = $Text
    $label.Location = [System.Drawing.Point]::new($X, $Y)
    $label.Size = [System.Drawing.Size]::new($Width, 23)
    $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    return $label
}

function Quote-Argument {
    param([string]$Value)
    '"' + ($Value -replace '(\\*)"', '$1$1\\"' -replace '(\\*)$', '$1$1') + '"'
}

function Get-AtlasImages {
    param([string]$Directory)
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { return @() }
    Get-ChildItem -LiteralPath $Directory -File -Recurse | Where-Object {
        $_.Extension -in '.jpg', '.jpeg', '.png'
    }
}

function Add-JpegComment {
    param([string]$ImagePath, [string]$Comment)

    if ([System.IO.Path]::GetExtension($ImagePath).ToLowerInvariant() -notin '.jpg', '.jpeg') { return $false }
    $image = $null
    $temporaryPath = "$ImagePath.atlasbuilder.tmp.jpg"
    try {
        $image = [System.Drawing.Image]::FromFile($ImagePath)
        $property = [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject([System.Drawing.Imaging.PropertyItem])
        $property.Id = 37510 # EXIF UserComment
        $property.Type = 7
        $property.Value = [System.Text.Encoding]::UTF8.GetBytes("ASCII`0`0`0$Comment")
        $property.Len = $property.Value.Length
        $image.SetPropertyItem($property)
        $image.Save($temporaryPath, [System.Drawing.Imaging.ImageFormat]::Jpeg)
        $image.Dispose()
        $image = $null
        Move-Item -LiteralPath $temporaryPath -Destination $ImagePath -Force
        return $true
    } catch {
        if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue }
        return $false
    } finally {
        if ($null -ne $image) { $image.Dispose() }
    }
}

function Save-AtlasMetadata {
    param(
        [pscustomobject]$Run,
        [hashtable]$BeforeImages
    )

    $images = Get-AtlasImages -Directory $Run.OutputPath | Where-Object {
        -not $BeforeImages.ContainsKey($_.FullName) -or $_.LastWriteTimeUtc -ge $Run.StartedAtUtc
    }

    $count = 0
    foreach ($image in $images) {
        $metadata = [ordered]@{
            SchemaVersion = 1
            ImageFileName = $image.Name
            ImagePath = $image.FullName
            GeneratedAtUtc = $Run.StartedAtUtc.ToString('o')
            Settings = $Run.Settings
        }
        $metadataPath = "$($image.FullName).riverheim.json"
        $metadata | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $metadataPath -Encoding UTF8
        $comment = "Riverheim AtlasBuilder | Seed=$($Run.Settings.Seed); Mode=$($Run.Settings.Mode); Resolution=$($Run.Settings.Resolution); Grid=$($Run.Settings.Grid); Whole=$($Run.Settings.Whole); Preset=$($Run.Settings.Preset)"
        [void](Add-JpegComment -ImagePath $image.FullName -Comment $comment)
        $count++
    }
    return $count
}

$form = [System.Windows.Forms.Form]::new()
$form.Text = 'Riverheim AtlasBuilder'
$form.ClientSize = [System.Drawing.Size]::new(950, 530)
$form.MinimumSize = [System.Drawing.Size]::new(966, 570)
$form.StartPosition = 'CenterScreen'
$form.Font = [System.Drawing.Font]::new('Segoe UI', 9)
$form.BackColor = [System.Drawing.Color]::FromArgb(248, 249, 250)

$title = [System.Windows.Forms.Label]::new()
$title.Text = 'Riverheim AtlasBuilder'
$title.Font = [System.Drawing.Font]::new('Segoe UI Semibold', 16)
$title.Location = [System.Drawing.Point]::new(18, 15)
$title.AutoSize = $true
$form.Controls.Add($title)

$subtitle = [System.Windows.Forms.Label]::new()
$subtitle.Text = 'Generate a map image from a Riverheim world seed.'
$subtitle.ForeColor = [System.Drawing.Color]::DimGray
$subtitle.Location = [System.Drawing.Point]::new(20, 43)
$subtitle.AutoSize = $true
$form.Controls.Add($subtitle)

$form.Controls.Add((New-Label 'AtlasBuilder' 18 78))
$exeBox = [System.Windows.Forms.TextBox]::new()
$exeBox.Location = [System.Drawing.Point]::new(125, 78)
$exeBox.Size = [System.Drawing.Size]::new(430, 23)
$exeBox.Anchor = 'Top, Left, Right'
$exeBox.Text = $defaultExe
$form.Controls.Add($exeBox)

$browseExe = [System.Windows.Forms.Button]::new()
$browseExe.Text = 'Browse...'
$browseExe.Location = [System.Drawing.Point]::new(564, 77)
$browseExe.Size = [System.Drawing.Size]::new(78, 25)
$browseExe.Anchor = 'Top, Right'
$form.Controls.Add($browseExe)

$form.Controls.Add((New-Label 'World seed' 18 115))
$seedBox = [System.Windows.Forms.TextBox]::new()
$seedBox.Location = [System.Drawing.Point]::new(125, 115)
$seedBox.Size = [System.Drawing.Size]::new(240, 23)
$form.Controls.Add($seedBox)

$form.Controls.Add((New-Label 'Output folder' 18 152))
$outputBox = [System.Windows.Forms.TextBox]::new()
$outputBox.Location = [System.Drawing.Point]::new(125, 152)
$outputBox.Size = [System.Drawing.Size]::new(430, 23)
$outputBox.Anchor = 'Top, Left, Right'
$outputBox.Text = $defaultOutput
$form.Controls.Add($outputBox)

$browseOutput = [System.Windows.Forms.Button]::new()
$browseOutput.Text = 'Browse...'
$browseOutput.Location = [System.Drawing.Point]::new(564, 151)
$browseOutput.Size = [System.Drawing.Size]::new(78, 25)
$browseOutput.Anchor = 'Top, Right'
$form.Controls.Add($browseOutput)

$allMapModes = [string[]]@('Rich', 'Landmass', 'Biomes', 'RichTerrain', 'Hdr')
$script:selectedModes = [string[]]@('Rich')
$form.Controls.Add((New-Label 'Map modes' 18 190))
$modeSummary = [System.Windows.Forms.TextBox]::new()
$modeSummary.Location = [System.Drawing.Point]::new(125, 190)
$modeSummary.Size = [System.Drawing.Size]::new(170, 23)
$modeSummary.ReadOnly = $true
$modeSummary.BackColor = [System.Drawing.Color]::White
$modeSummary.Text = 'Rich'
$form.Controls.Add($modeSummary)

$chooseModesButton = [System.Windows.Forms.Button]::new()
$chooseModesButton.Text = 'Choose...'
$chooseModesButton.Location = [System.Drawing.Point]::new(303, 189)
$chooseModesButton.Size = [System.Drawing.Size]::new(76, 25)
$form.Controls.Add($chooseModesButton)

$form.Controls.Add((New-Label 'Resolution' 400 190 72))
$resolutionBox = [System.Windows.Forms.ComboBox]::new()
$resolutionBox.Location = [System.Drawing.Point]::new(475, 190)
$resolutionBox.Size = [System.Drawing.Size]::new(100, 23)
$resolutionBox.DropDownStyle = 'DropDownList'
[void]$resolutionBox.Items.AddRange([string[]]@('256', '512', '1024', '2048', '4096'))
$resolutionBox.SelectedItem = '1024'
$form.Controls.Add($resolutionBox)

$form.Controls.Add((New-Label 'World count' 600 190 75))
$countBox = [System.Windows.Forms.NumericUpDown]::new()
$countBox.Location = [System.Drawing.Point]::new(680, 190)
$countBox.Size = [System.Drawing.Size]::new(78, 23)
$countBox.Minimum = -1
$countBox.Maximum = 1000
$countBox.Value = -1
$form.Controls.Add($countBox)

$gridBox = [System.Windows.Forms.CheckBox]::new()
$gridBox.Text = 'Draw grid'
$gridBox.Location = [System.Drawing.Point]::new(125, 225)
$gridBox.AutoSize = $true
$form.Controls.Add($gridBox)

$wholeBox = [System.Windows.Forms.CheckBox]::new()
$wholeBox.Text = 'Create one whole atlas image'
$wholeBox.Location = [System.Drawing.Point]::new(225, 225)
$wholeBox.AutoSize = $true
$form.Controls.Add($wholeBox)

$toolTip = [System.Windows.Forms.ToolTip]::new()
$toolTip.SetToolTip($wholeBox, 'Whole atlas needs World count 1 or more. Exact seed mode (-1) is not supported by AtlasBuilder for this output.')
$wholeBox.Add_CheckedChanged({
    if ($wholeBox.Checked -and $countBox.Value -lt 1) {
        $countBox.Value = 1
        $status.Text = 'Whole atlas uses a positive world count.'
    }
    $countBox.Minimum = if ($wholeBox.Checked) { 1 } else { -1 }
})

$form.Controls.Add((New-Label 'Preset' 420 223 48))
$presetBox = [System.Windows.Forms.TextBox]::new()
$presetBox.Location = [System.Drawing.Point]::new(469, 222)
$presetBox.Size = [System.Drawing.Size]::new(173, 23)
$presetBox.Text = 'Default'
$form.Controls.Add($presetBox)

$runButton = [System.Windows.Forms.Button]::new()
$runButton.Text = 'Generate map'
$runButton.Location = [System.Drawing.Point]::new(18, 264)
$runButton.Size = [System.Drawing.Size]::new(120, 32)
$runButton.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 212)
$runButton.ForeColor = [System.Drawing.Color]::White
$runButton.FlatStyle = 'Flat'
$form.Controls.Add($runButton)

$openButton = [System.Windows.Forms.Button]::new()
$openButton.Text = 'Open output folder'
$openButton.Location = [System.Drawing.Point]::new(147, 264)
$openButton.Size = [System.Drawing.Size]::new(130, 32)
$form.Controls.Add($openButton)

$historyButton = [System.Windows.Forms.Button]::new()
$historyButton.Text = 'Map history'
$historyButton.Location = [System.Drawing.Point]::new(286, 264)
$historyButton.Size = [System.Drawing.Size]::new(95, 32)
$form.Controls.Add($historyButton)

$guideButton = [System.Windows.Forms.Button]::new()
$guideButton.Text = 'Settings guide'
$guideButton.Location = [System.Drawing.Point]::new(390, 264)
$guideButton.Size = [System.Drawing.Size]::new(100, 32)
$form.Controls.Add($guideButton)

$status = [System.Windows.Forms.Label]::new()
$status.Text = 'Ready'
$status.Location = [System.Drawing.Point]::new(500, 270)
$status.Size = [System.Drawing.Size]::new(432, 23)
$status.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$status.Anchor = 'Top, Right'
$form.Controls.Add($status)

$activityTitle = [System.Windows.Forms.Label]::new()
$activityTitle.Text = 'Activity'
$activityTitle.Location = [System.Drawing.Point]::new(18, 311)
$activityTitle.AutoSize = $true
$activityTitle.Font = [System.Drawing.Font]::new('Segoe UI Semibold', 9)
$form.Controls.Add($activityTitle)

$logBox = [System.Windows.Forms.TextBox]::new()
$logBox.Location = [System.Drawing.Point]::new(18, 336)
$logBox.Size = [System.Drawing.Size]::new(595, 175)
$logBox.Anchor = 'Top, Bottom, Left'
$logBox.Multiline = $true
$logBox.ReadOnly = $true
$logBox.ScrollBars = 'Vertical'
$logBox.BackColor = [System.Drawing.Color]::White
$logBox.Font = [System.Drawing.Font]::new('Cascadia Mono', 9)
$form.Controls.Add($logBox)

$previewTitle = [System.Windows.Forms.Label]::new()
$previewTitle.Text = 'Latest map'
$previewTitle.Location = [System.Drawing.Point]::new(632, 311)
$previewTitle.AutoSize = $true
$previewTitle.Font = [System.Drawing.Font]::new('Segoe UI Semibold', 9)
$previewTitle.Anchor = 'Top, Right'
$form.Controls.Add($previewTitle)

$mainPreview = [System.Windows.Forms.PictureBox]::new()
$mainPreview.Location = [System.Drawing.Point]::new(632, 336)
$mainPreview.Size = [System.Drawing.Size]::new(300, 145)
$mainPreview.BorderStyle = 'FixedSingle'
$mainPreview.SizeMode = 'Zoom'
$mainPreview.Anchor = 'Top, Bottom, Right'
$form.Controls.Add($mainPreview)

$previewInfo = [System.Windows.Forms.Label]::new()
$previewInfo.Text = 'No map selected'
$previewInfo.Location = [System.Drawing.Point]::new(632, 486)
$previewInfo.Size = [System.Drawing.Size]::new(205, 23)
$previewInfo.AutoEllipsis = $true
$previewInfo.Anchor = 'Bottom, Right'
$form.Controls.Add($previewInfo)

$openPreviewButton = [System.Windows.Forms.Button]::new()
$openPreviewButton.Text = 'Open'
$openPreviewButton.Location = [System.Drawing.Point]::new(852, 483)
$openPreviewButton.Size = [System.Drawing.Size]::new(80, 28)
$openPreviewButton.Anchor = 'Bottom, Right'
$openPreviewButton.Enabled = $false
$form.Controls.Add($openPreviewButton)

$appendLog = {
    param([string]$Text)
    if ($Text) { $logBox.AppendText($Text + [Environment]::NewLine) }
}

function Update-MainPreview {
    param([string]$Directory)
    $latest = Get-AtlasImages -Directory $Directory | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if ($null -eq $latest) {
        $mainPreview.Image = $null
        $previewInfo.Text = 'No generated map found'
        $openPreviewButton.Enabled = $false
        $script:mainPreviewPath = $null
        return
    }
    try {
        $source = [System.Drawing.Image]::FromFile($latest.FullName)
        $replacement = [System.Drawing.Bitmap]::new($source)
        $source.Dispose()
        if ($null -ne $mainPreview.Image) { $mainPreview.Image.Dispose() }
        $mainPreview.Image = $replacement
        $previewInfo.Text = $latest.Name
        $script:mainPreviewPath = $latest.FullName
        $openPreviewButton.Enabled = $true
    } catch {
        $previewInfo.Text = 'Preview unavailable'
    }
}

function Update-ModeSummary {
    if ($script:selectedModes.Count -eq $allMapModes.Count) {
        $modeSummary.Text = 'All 5 modes'
    } elseif ($script:selectedModes.Count -eq 1) {
        $modeSummary.Text = $script:selectedModes[0]
    } else {
        $modeSummary.Text = "$($script:selectedModes.Count) modes selected"
    }
}

function Show-MapModeChooser {
    $dialog = [System.Windows.Forms.Form]::new()
    $dialog.Text = 'Choose Map Modes'
    $dialog.ClientSize = [System.Drawing.Size]::new(280, 290)
    $dialog.StartPosition = 'CenterParent'
    $dialog.Font = [System.Drawing.Font]::new('Segoe UI', 9)

    $list = [System.Windows.Forms.CheckedListBox]::new()
    $list.Location = [System.Drawing.Point]::new(16, 16)
    $list.Size = [System.Drawing.Size]::new(248, 165)
    $list.CheckOnClick = $true
    [void]$list.Items.AddRange($allMapModes)
    for ($index = 0; $index -lt $list.Items.Count; $index++) {
        $list.SetItemChecked($index, $script:selectedModes -contains $list.Items[$index])
    }
    $dialog.Controls.Add($list)

    $allButton = [System.Windows.Forms.Button]::new()
    $allButton.Text = 'Select all'
    $allButton.Location = [System.Drawing.Point]::new(16, 194)
    $allButton.Size = [System.Drawing.Size]::new(90, 28)
    $dialog.Controls.Add($allButton)

    $clearButton = [System.Windows.Forms.Button]::new()
    $clearButton.Text = 'Clear'
    $clearButton.Location = [System.Drawing.Point]::new(114, 194)
    $clearButton.Size = [System.Drawing.Size]::new(70, 28)
    $dialog.Controls.Add($clearButton)

    $applyButton = [System.Windows.Forms.Button]::new()
    $applyButton.Text = 'Apply'
    $applyButton.Location = [System.Drawing.Point]::new(174, 242)
    $applyButton.Size = [System.Drawing.Size]::new(90, 30)
    $dialog.Controls.Add($applyButton)

    $allButton.Add_Click({ for ($index = 0; $index -lt $list.Items.Count; $index++) { $list.SetItemChecked($index, $true) } })
    $clearButton.Add_Click({ for ($index = 0; $index -lt $list.Items.Count; $index++) { $list.SetItemChecked($index, $false) } })
    $applyButton.Add_Click({
        $selected = @($list.CheckedItems | ForEach-Object { $_.ToString() })
        if ($selected.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show('Choose at least one map mode.', 'Map mode required', 'OK', 'Warning') | Out-Null
            return
        }
        $script:selectedModes = [string[]]$selected
        Update-ModeSummary
        $dialog.Close()
    })
    [void]$dialog.ShowDialog($form)
}

function Show-SettingsGuide {
    $guide = [System.Windows.Forms.Form]::new()
    $guide.Text = 'AtlasBuilder Settings Guide'
    $guide.ClientSize = [System.Drawing.Size]::new(600, 425)
    $guide.StartPosition = 'CenterParent'
    $guide.Font = [System.Drawing.Font]::new('Segoe UI', 9)
    $text = [System.Windows.Forms.TextBox]::new()
    $text.Dock = 'Fill'
    $text.Multiline = $true
    $text.ReadOnly = $true
    $text.ScrollBars = 'Vertical'
    $text.BackColor = [System.Drawing.Color]::White
    $text.Font = [System.Drawing.Font]::new('Segoe UI', 10)
    $text.Text = @'
AtlasBuilder
The Riverheim.AtlasBuilder.exe program used to create maps. Leave this on its detected path unless your Thunderstore profile moved.

World seed
Your Valheim world seed. With World count set to -1, AtlasBuilder renders this exact seed.

Map modes
Choose one or more render styles. The launcher renders the selected styles one after another with the same seed, placing each style in its own output subfolder so no image is overwritten. Rich is the normal detailed colour view; Landmass focuses on land and water shapes; Biomes visualizes biome regions; RichTerrain emphasizes terrain; Hdr is the tool's high-dynamic-range style.

Resolution
The output size in pixels. Larger values are sharper but need more time and memory.

World count
-1 renders the exact seed once. A positive number renders that many derived seeds. Whole atlas needs a positive count because it combines those generated maps.

Draw grid
Adds a coordinate grid on top of each map image.

Create one whole atlas image
Combines generated maps into one image. It cannot be used with exact-seed mode (-1) in AtlasBuilder 1.0.0.

Preset
AtlasBuilder's generation preset. Default is the package default.

Map history
Saved image settings are stored beside each image. Filter the thumbnail stack by Map mode or grid state, open a map, or load its settings back into the launcher.
'@
    $guide.Controls.Add($text)
    [void]$guide.ShowDialog($form)
}

$completionTimer = [System.Windows.Forms.Timer]::new()
$completionTimer.Interval = 500
$completionTimer.Add_Tick({
    $process = $script:activeProcess
    if ($null -eq $process -or -not $process.HasExited) { return }

    $completionTimer.Stop()
    $exitCode = $process.ExitCode
    $script:activeProcess = $null
    if ($exitCode -eq 0) {
        & $appendLog "Finished $($script:activeGeneration.Settings.Mode)."
        try {
            $saved = Save-AtlasMetadata -Run $script:activeGeneration -BeforeImages $script:activeBeforeImages
            if ($saved -gt 0) {
                & $appendLog "Saved settings alongside $saved generated image(s)."
                Update-MainPreview -Directory $script:activeGeneration.OutputPath
            } else {
                & $appendLog 'No new JPG or PNG files were found to tag.'
            }
        } catch {
            & $appendLog "Could not save map metadata: $($_.Exception.Message)"
        }
        $script:completedModeCount++
        if ($script:generationQueue.Count -gt 0) {
            Start-NextGeneration
        } else {
            $runButton.Enabled = $true
            $status.Text = "Finished $($script:completedModeCount) of $($script:totalModeCount) selected mode(s)."
        }
    } else {
        $script:generationQueue.Clear()
        $runButton.Enabled = $true
        $status.Text = "Stopped with exit code $exitCode"
        & $appendLog "Stopped with exit code $exitCode. Check the AtlasBuilder console window for details."
    }
})

function Start-NextGeneration {
    if ($script:generationQueue.Count -eq 0) { return }

    $mode = $script:generationQueue.Dequeue()
    $batch = $script:batchRun
    $modeOutputPath = Join-Path $batch.OutputPath $mode
    [void](New-Item -ItemType Directory -Path $modeOutputPath -Force)
    $arguments = @(
        '--path', (Quote-Argument $modeOutputPath),
        '--seed', (Quote-Argument $batch.Seed),
        '--mode', $mode,
        '--resolution', $batch.Resolution,
        '--count', $batch.Count,
        '--preset', (Quote-Argument $batch.Preset)
    )
    if ($batch.Grid) { $arguments += '--grid' }
    if ($batch.Whole) { $arguments += '--whole' }

    $beforeImages = @{}
    foreach ($image in (Get-AtlasImages -Directory $modeOutputPath)) { $beforeImages[$image.FullName] = $image.LastWriteTimeUtc }
    $script:activeGeneration = [pscustomobject]@{
        StartedAtUtc = [DateTime]::UtcNow
        OutputPath = $modeOutputPath
        Settings = [ordered]@{
            Seed = $batch.Seed
            Mode = $mode
            Resolution = [int]$batch.Resolution
            Count = [int]$batch.Count
            Grid = $batch.Grid
            Whole = $batch.Whole
            Preset = $batch.Preset
            Executable = $batch.Executable
        }
    }
    $script:activeBeforeImages = $beforeImages

    & $appendLog "Running $mode ($($script:completedModeCount + 1)/$($script:totalModeCount)): $($batch.Executable) $($arguments -join ' ')"
    $status.Text = "Generating $mode ($($script:completedModeCount + 1) of $($script:totalModeCount))..."

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo.FileName = $batch.Executable
    $process.StartInfo.Arguments = $arguments -join ' '
    $process.StartInfo.UseShellExecute = $true
    try {
        [void]$process.Start()
        $script:activeProcess = $process
        $completionTimer.Start()
    } catch {
        $script:generationQueue.Clear()
        $runButton.Enabled = $true
        $status.Text = 'Could not start'
        & $appendLog "ERROR: $($_.Exception.Message)"
    }
}

function Show-MapHistory {
    $browser = [System.Windows.Forms.Form]::new()
    $browser.Text = 'Riverheim Map History'
    $browser.ClientSize = [System.Drawing.Size]::new(900, 530)
    $browser.MinimumSize = [System.Drawing.Size]::new(760, 480)
    $browser.StartPosition = 'CenterParent'
    $browser.Font = [System.Drawing.Font]::new('Segoe UI', 9)

    $browser.Controls.Add((New-Label 'Map folder' 14 15 70))
    $folderBox = [System.Windows.Forms.TextBox]::new()
    $folderBox.Location = [System.Drawing.Point]::new(88, 15)
    $folderBox.Size = [System.Drawing.Size]::new(620, 23)
    $folderBox.Anchor = 'Top, Left, Right'
    $folderBox.Text = $outputBox.Text.Trim()
    $browser.Controls.Add($folderBox)

    $chooseFolder = [System.Windows.Forms.Button]::new()
    $chooseFolder.Text = 'Browse...'
    $chooseFolder.Location = [System.Drawing.Point]::new(716, 14)
    $chooseFolder.Size = [System.Drawing.Size]::new(78, 25)
    $chooseFolder.Anchor = 'Top, Right'
    $browser.Controls.Add($chooseFolder)

    $refresh = [System.Windows.Forms.Button]::new()
    $refresh.Text = 'Refresh'
    $refresh.Location = [System.Drawing.Point]::new(802, 14)
    $refresh.Size = [System.Drawing.Size]::new(82, 25)
    $refresh.Anchor = 'Top, Right'
    $browser.Controls.Add($refresh)

    $browser.Controls.Add((New-Label 'Mode' 14 50 38))
    $modeFilter = [System.Windows.Forms.ComboBox]::new()
    $modeFilter.Location = [System.Drawing.Point]::new(54, 50)
    $modeFilter.Size = [System.Drawing.Size]::new(126, 23)
    $modeFilter.DropDownStyle = 'DropDownList'
    [void]$modeFilter.Items.AddRange([string[]]@('All modes', 'Rich', 'Landmass', 'Biomes', 'RichTerrain', 'Hdr'))
    $modeFilter.SelectedIndex = 0
    $browser.Controls.Add($modeFilter)

    $browser.Controls.Add((New-Label 'Grid' 200 50 32))
    $gridFilter = [System.Windows.Forms.ComboBox]::new()
    $gridFilter.Location = [System.Drawing.Point]::new(235, 50)
    $gridFilter.Size = [System.Drawing.Size]::new(112, 23)
    $gridFilter.DropDownStyle = 'DropDownList'
    [void]$gridFilter.Items.AddRange([string[]]@('Any grid', 'Grid on', 'Grid off'))
    $gridFilter.SelectedIndex = 0
    $browser.Controls.Add($gridFilter)

    $list = [System.Windows.Forms.ListView]::new()
    $list.Location = [System.Drawing.Point]::new(14, 86)
    $list.Size = [System.Drawing.Size]::new(510, 378)
    $list.Anchor = 'Top, Bottom, Left'
    $list.View = 'Tile'
    $list.TileSize = [System.Drawing.Size]::new(490, 82)
    $list.FullRowSelect = $true
    $list.MultiSelect = $false
    $thumbnails = [System.Windows.Forms.ImageList]::new()
    $thumbnails.ImageSize = [System.Drawing.Size]::new(96, 64)
    $thumbnails.ColorDepth = 'Depth32Bit'
    $list.LargeImageList = $thumbnails
    $browser.Controls.Add($list)

    $preview = [System.Windows.Forms.PictureBox]::new()
    $preview.Location = [System.Drawing.Point]::new(540, 86)
    $preview.Size = [System.Drawing.Size]::new(344, 230)
    $preview.Anchor = 'Top, Right'
    $preview.BorderStyle = 'FixedSingle'
    $preview.SizeMode = 'Zoom'
    $browser.Controls.Add($preview)

    $details = [System.Windows.Forms.TextBox]::new()
    $details.Location = [System.Drawing.Point]::new(540, 326)
    $details.Size = [System.Drawing.Size]::new(344, 138)
    $details.Anchor = 'Top, Bottom, Right'
    $details.ReadOnly = $true
    $details.Multiline = $true
    $details.ScrollBars = 'Vertical'
    $details.BackColor = [System.Drawing.Color]::White
    $browser.Controls.Add($details)

    $load = [System.Windows.Forms.Button]::new()
    $load.Text = 'Load settings'
    $load.Location = [System.Drawing.Point]::new(14, 478)
    $load.Size = [System.Drawing.Size]::new(105, 30)
    $load.Anchor = 'Bottom, Left'
    $browser.Controls.Add($load)

    $openImage = [System.Windows.Forms.Button]::new()
    $openImage.Text = 'Open image'
    $openImage.Location = [System.Drawing.Point]::new(128, 478)
    $openImage.Size = [System.Drawing.Size]::new(95, 30)
    $openImage.Anchor = 'Bottom, Left'
    $browser.Controls.Add($openImage)

    $openFolder = [System.Windows.Forms.Button]::new()
    $openFolder.Text = 'Open folder'
    $openFolder.Location = [System.Drawing.Point]::new(232, 478)
    $openFolder.Size = [System.Drawing.Size]::new(95, 30)
    $openFolder.Anchor = 'Bottom, Left'
    $browser.Controls.Add($openFolder)

    $showSelected = {
        if ($list.SelectedItems.Count -eq 0) { return }
        $record = $list.SelectedItems[0].Tag
        $imagePath = $record.ImagePath
        if (-not (Test-Path -LiteralPath $imagePath)) { $imagePath = $record.SidecarPath -replace '\.riverheim\.json$', '' }
        $preview.Image = $null
        if (Test-Path -LiteralPath $imagePath) {
            try {
                $source = [System.Drawing.Image]::FromFile($imagePath)
                $preview.Image = [System.Drawing.Bitmap]::new($source)
                $source.Dispose()
            } catch { }
        }
        $settings = $record.Settings
        $details.Text = "Seed: $($settings.Seed)`r`nMode: $($settings.Mode)`r`nResolution: $($settings.Resolution)`r`nWorld count: $($settings.Count)`r`nGrid: $($settings.Grid)`r`nWhole atlas: $($settings.Whole)`r`nPreset: $($settings.Preset)`r`nGenerated: $($record.GeneratedAtUtc)"
    }

    $refreshList = {
        $list.Items.Clear()
        $thumbnails.Images.Clear()
        if ($null -ne $preview.Image) { $preview.Image.Dispose(); $preview.Image = $null }
        $details.Clear()
        $folder = $folderBox.Text.Trim()
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) { return }
        $imageIndex = 0
        Get-ChildItem -LiteralPath $folder -Filter '*.riverheim.json' -File -Recurse | Sort-Object LastWriteTimeUtc -Descending | ForEach-Object {
            try {
                $record = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
                $record | Add-Member -NotePropertyName SidecarPath -NotePropertyValue $_.FullName -Force
                if ($modeFilter.SelectedItem -ne 'All modes' -and $record.Settings.Mode -ne $modeFilter.SelectedItem) { return }
                if ($gridFilter.SelectedItem -eq 'Grid on' -and -not [bool]$record.Settings.Grid) { return }
                if ($gridFilter.SelectedItem -eq 'Grid off' -and [bool]$record.Settings.Grid) { return }
                $item = [System.Windows.Forms.ListViewItem]::new([string]$record.ImageFileName)
                [void]$item.SubItems.Add("Seed: $($record.Settings.Seed)")
                $gridText = if ([bool]$record.Settings.Grid) { 'Grid' } else { 'No grid' }
                [void]$item.SubItems.Add("$($record.Settings.Mode) | $($record.Settings.Resolution) px | $gridText")
                $imagePath = $record.ImagePath
                if (-not (Test-Path -LiteralPath $imagePath)) { $imagePath = $_.FullName -replace '\.riverheim\.json$', '' }
                if (Test-Path -LiteralPath $imagePath) {
                    try {
                        $source = [System.Drawing.Image]::FromFile($imagePath)
                        $thumbnail = [System.Drawing.Bitmap]::new($source, 96, 64)
                        $source.Dispose()
                        $key = "image-$imageIndex"
                        $thumbnails.Images.Add($key, $thumbnail)
                        $item.ImageKey = $key
                        $imageIndex++
                    } catch { }
                }
                $item.Tag = $record
                [void]$list.Items.Add($item)
            } catch { }
        }
    }

    $chooseFolder.Add_Click({
        $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
        if (Test-Path -LiteralPath $folderBox.Text) { $dialog.SelectedPath = $folderBox.Text }
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $folderBox.Text = $dialog.SelectedPath
            & $refreshList
        }
    })
    $refresh.Add_Click($refreshList)
    $modeFilter.Add_SelectedIndexChanged($refreshList)
    $gridFilter.Add_SelectedIndexChanged($refreshList)
    $list.Add_SelectedIndexChanged($showSelected)
    $list.Add_DoubleClick({ & $showSelected; $load.PerformClick() })
    $load.Add_Click({
        if ($list.SelectedItems.Count -eq 0) { return }
        $record = $list.SelectedItems[0].Tag
        $settings = $record.Settings
        $seedBox.Text = $settings.Seed
        $script:selectedModes = [string[]]@([string]$settings.Mode)
        Update-ModeSummary
        $resolutionBox.SelectedItem = [string]$settings.Resolution
        $countBox.Value = [decimal]$settings.Count
        $gridBox.Checked = [bool]$settings.Grid
        $wholeBox.Checked = [bool]$settings.Whole
        $presetBox.Text = $settings.Preset
        $outputBox.Text = Split-Path -Parent $record.SidecarPath
        $browser.Close()
    })
    $openImage.Add_Click({
        if ($list.SelectedItems.Count -eq 0) { return }
        $record = $list.SelectedItems[0].Tag
        if (Test-Path -LiteralPath $record.ImagePath) { Start-Process -FilePath $record.ImagePath }
    })
    $openFolder.Add_Click({
        if ($list.SelectedItems.Count -eq 0) { return }
        $record = $list.SelectedItems[0].Tag
        Start-Process -FilePath explorer.exe -ArgumentList (Quote-Argument (Split-Path -Parent $record.SidecarPath))
    })
    $browser.Add_FormClosed({
        if ($null -ne $preview.Image) { $preview.Image.Dispose() }
        $thumbnails.Dispose()
    })

    & $refreshList
    [void]$browser.ShowDialog($form)
}

$browseExe.Add_Click({
    $dialog = [System.Windows.Forms.OpenFileDialog]::new()
    $dialog.Filter = 'AtlasBuilder executable|Riverheim.AtlasBuilder.exe|Executables|*.exe'
    if (Test-Path -LiteralPath $exeBox.Text) { $dialog.InitialDirectory = Split-Path -Parent $exeBox.Text }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $exeBox.Text = $dialog.FileName }
})

$browseOutput.Add_Click({
    $dialog = [System.Windows.Forms.FolderBrowserDialog]::new()
    $dialog.Description = 'Choose where generated map images will be saved'
    if (Test-Path -LiteralPath $outputBox.Text) { $dialog.SelectedPath = $outputBox.Text }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $outputBox.Text = $dialog.SelectedPath }
})

$historyButton.Add_Click({ Show-MapHistory })
$chooseModesButton.Add_Click({ Show-MapModeChooser })
$guideButton.Add_Click({ Show-SettingsGuide })
$openPreviewButton.Add_Click({
    if ($script:mainPreviewPath -and (Test-Path -LiteralPath $script:mainPreviewPath)) {
        Start-Process -FilePath $script:mainPreviewPath
    }
})
$form.Add_Shown({ Update-MainPreview -Directory $outputBox.Text.Trim() })
$form.Add_FormClosed({ if ($null -ne $mainPreview.Image) { $mainPreview.Image.Dispose() } })

$openButton.Add_Click({
    $path = $outputBox.Text.Trim()
    if (-not $path) { return }
    if (-not (Test-Path -LiteralPath $path)) { [void](New-Item -ItemType Directory -Path $path -Force) }
    Start-Process -FilePath explorer.exe -ArgumentList (Quote-Argument $path)
})

$runButton.Add_Click({
    $exe = $exeBox.Text.Trim()
    $seed = $seedBox.Text.Trim()
    $output = $outputBox.Text.Trim()

    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show('Choose the Riverheim.AtlasBuilder.exe file.', 'AtlasBuilder not found', 'OK', 'Warning') | Out-Null
        return
    }
    if (-not $seed) {
        [System.Windows.Forms.MessageBox]::Show('Enter your Valheim world seed.', 'World seed required', 'OK', 'Warning') | Out-Null
        return
    }
    if (-not $output) {
        [System.Windows.Forms.MessageBox]::Show('Choose an output folder.', 'Output folder required', 'OK', 'Warning') | Out-Null
        return
    }
    if ($script:selectedModes.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('Choose at least one map mode.', 'Map mode required', 'OK', 'Warning') | Out-Null
        return
    }
    if ($wholeBox.Checked -and $countBox.Value -lt 1) {
        [System.Windows.Forms.MessageBox]::Show('Whole atlas requires World count 1 or more. AtlasBuilder cannot build it from exact seed mode (-1).', 'Whole atlas requires a count', 'OK', 'Warning') | Out-Null
        return
    }

    try { [void](New-Item -ItemType Directory -Path $output -Force) }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Could not create the output folder.`n$($_.Exception.Message)", 'Output folder error', 'OK', 'Error') | Out-Null
        return
    }

    $script:batchRun = [pscustomobject]@{
        Executable = $exe
        Seed = $seed
        OutputPath = $output
        Resolution = $resolutionBox.SelectedItem.ToString()
        Count = [int]$countBox.Value
        Grid = $gridBox.Checked
        Whole = $wholeBox.Checked
        Preset = $presetBox.Text.Trim()
    }
    $script:generationQueue = [System.Collections.Generic.Queue[string]]::new()
    foreach ($mode in $script:selectedModes) { $script:generationQueue.Enqueue($mode) }
    $script:totalModeCount = $script:generationQueue.Count
    $script:completedModeCount = 0
    $logBox.Clear()
    $runButton.Enabled = $false
    Start-NextGeneration
})

[void]$form.ShowDialog()

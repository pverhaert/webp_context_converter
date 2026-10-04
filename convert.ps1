#requires -Version 5.1
param(
    [Parameter(Position = 0)]
    [string]$FilePath,

    [Parameter(Position = 1)]
    [string]$Quality = "70",

    [Parameter()]
    [string]$JobId = ""
)

function Find-MagickExecutable {
    # 1. Check if 'magick' is available in current PATH
    $cmd = Get-Command magick -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    # 2. Check standard Program Files installation paths as fallback
    $searchPaths = @(
        "$env:ProgramFiles\ImageMagick*",
        "${env:ProgramFiles(x86)}\ImageMagick*",
        "$env:LOCALAPPDATA\Programs\ImageMagick*"
    )

    foreach ($pathPattern in $searchPaths) {
        $dirs = Get-ChildItem -Path $pathPattern -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending
        foreach ($d in $dirs) {
            $candidate = Join-Path $d.FullName "magick.exe"
            if (Test-Path -LiteralPath $candidate) {
                return $candidate
            }
        }
    }

    return $null
}

function Format-FileSize([long]$bytes) {
    if ($bytes -ge 1GB) { return "$([Math]::Round($bytes / 1GB, 2)) GB" }
    if ($bytes -ge 1MB) { return "$([Math]::Round($bytes / 1MB, 2)) MB" }
    if ($bytes -ge 1KB) { return "$([Math]::Round($bytes / 1KB, 1)) KB" }
    return "$bytes B"
}

function Show-ToastNotification {
    param(
        [string]$Title,
        [string]$Message,
        [string]$IconPath = ""
    )

    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

        $imageXml = ""
        if ($IconPath -and (Test-Path -LiteralPath $IconPath)) {
            $imageUri = [System.Uri]::new((Resolve-Path -LiteralPath $IconPath).Path).AbsoluteUri
            $imageXml = "<image placement=""appLogoOverride"" src=""$imageUri"" hint-crop=""circle""/>"
        }

        # XML encode strings
        $safeTitle = [System.Security.SecurityElement]::Escape($Title)
        $lines = $Message -split "`n"
        $linesXml = ""
        foreach ($line in $lines) {
            $safeLine = [System.Security.SecurityElement]::Escape($line)
            $linesXml += "<text>$safeLine</text>"
        }

        $template = @"
<toast>
    <visual>
        <binding template="ToastGeneric">
            <text>$safeTitle</text>
            $linesXml
            $imageXml
        </binding>
    </visual>
</toast>
"@

        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml($template)
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe")
        $notifier.Show($toast)
    }
    catch {
        # Fallback silent
    }
}

function Process-BatchToastNotification {
    param(
        [string]$BatchDir,
        [string]$IconPath
    )

    # Purge any stale pending markers older than 45 seconds (in case of a crashed process)
    $cutoff = (Get-Date).AddSeconds(-45)
    Get-ChildItem -LiteralPath $BatchDir -Filter "*.pending" -ErrorAction SilentlyContinue | Where-Object {
        $_.LastWriteTime -lt $cutoff
    } | Remove-Item -Force -ErrorAction SilentlyContinue

    $mutex = $null
    $hasMutex = $false
    try {
        $mutex = New-Object System.Threading.Mutex($false, "Local\WebPConverter_Batch_Mutex")
        # Non-blocking acquisition attempt: returns true if this process becomes the coordinator
        $hasMutex = $mutex.WaitOne(0)
    } catch {
        $hasMutex = $false
    }

    if (-not $hasMutex) {
        # Another process is already acting as the coordinator and will show the consolidated toast
        return
    }

    try {
        # Coordinator loop: wait until all pending conversions finish
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $maxWaitMs = 120000 # 2 minute max timeout

        while ($sw.ElapsedMilliseconds -lt $maxWaitMs) {
            $pendingCount = (Get-ChildItem -LiteralPath $BatchDir -Filter "*.pending" -ErrorAction SilentlyContinue).Count
            if ($pendingCount -eq 0) {
                # Brief pause to verify no new pending items are actively starting
                Start-Sleep -Milliseconds 200
                $pendingCount = (Get-ChildItem -LiteralPath $BatchDir -Filter "*.pending" -ErrorAction SilentlyContinue).Count
                if ($pendingCount -eq 0) {
                    break
                }
            }
            Start-Sleep -Milliseconds 100
        }

        # Gather all completed results
        $doneFiles = Get-ChildItem -LiteralPath $BatchDir -Filter "*.done" -ErrorAction SilentlyContinue
        if ($doneFiles.Count -eq 0) {
            return
        }

        $results = @()
        foreach ($df in $doneFiles) {
            try {
                $raw = [System.IO.File]::ReadAllText($df.FullName)
                $data = $raw | ConvertFrom-Json
                $results += $data
            } catch {}
            Remove-Item -LiteralPath $df.FullName -Force -ErrorAction SilentlyContinue
        }

        if ($results.Count -eq 0) {
            return
        }

        # Format and display a SINGLE toast notification
        if ($results.Count -eq 1) {
            # Single file conversion
            $r = $results[0]
            if ($r.Success) {
                $origFmt = Format-FileSize $r.OrigSize
                $newFmt = Format-FileSize $r.NewSize
                if ($r.OrigSize -gt 0) {
                    $diff = $r.OrigSize - $r.NewSize
                    $pct = [Math]::Round(($diff / $r.OrigSize) * 100, 1)
                    if ($pct -gt 0) {
                        $statusText = "$origFmt -> $newFmt (-$pct%)"
                    } elseif ($pct -lt 0) {
                        $diffPct = [Math]::Abs($pct)
                        $statusText = "$origFmt -> $newFmt (+$diffPct%)"
                    } else {
                        $statusText = "$newFmt (unchanged)"
                    }
                } else {
                    $statusText = $newFmt
                }

                Show-ToastNotification `
                    -Title "WebP Conversion Completed ($($r.QualityLabel))" `
                    -Message "$($r.BaseName).webp`n$statusText" `
                    -IconPath $IconPath
            } else {
                Show-ToastNotification `
                    -Title "WebP Conversion Failed" `
                    -Message "Failed to convert $($r.BaseName).`nCheck if file format is supported and valid." `
                    -IconPath $IconPath
            }
        } else {
            # Multi-file batch conversion
            $successItems = @($results | Where-Object { $_.Success -eq $true })
            $failItems = @($results | Where-Object { $_.Success -ne $true })
            $totalCount = $results.Count
            $successCount = $successItems.Count
            $failCount = $failItems.Count

            $totalOrig = 0
            $totalNew = 0
            foreach ($item in $successItems) {
                $totalOrig += [long]$item.OrigSize
                $totalNew += [long]$item.NewSize
            }

            $firstQualityLabel = ($results | Select-Object -First 1).QualityLabel

            if ($successCount -eq $totalCount) {
                $title = "WebP Conversion Completed ($totalCount files)"
                $origFmt = Format-FileSize $totalOrig
                $newFmt = Format-FileSize $totalNew
                if ($totalOrig -gt 0) {
                    $diff = $totalOrig - $totalNew
                    $pct = [Math]::Round(($diff / $totalOrig) * 100, 1)
                    if ($pct -gt 0) {
                        $savings = "Total: $origFmt -> $newFmt (-$pct%)"
                    } else {
                        $savings = "Total: $origFmt -> $newFmt"
                    }
                } else {
                    $savings = "Total: $newFmt"
                }

                $msg = "$totalCount images converted ($firstQualityLabel)`n$savings"
            } elseif ($successCount -gt 0) {
                $title = "WebP Conversion Completed ($successCount/$totalCount files)"
                $origFmt = Format-FileSize $totalOrig
                $newFmt = Format-FileSize $totalNew
                $msg = "$successCount succeeded ($firstQualityLabel), $failCount failed`nTotal: $origFmt -> $newFmt"
            } else {
                $title = "WebP Conversion Failed ($totalCount files)"
                $msg = "All $totalCount image conversions failed."
            }

            Show-ToastNotification `
                -Title $title `
                -Message $msg `
                -IconPath $IconPath
        }
    }
    finally {
        if ($hasMutex -and $mutex) {
            try {
                $mutex.ReleaseMutex()
                $mutex.Dispose()
            } catch {}
        }
    }
}

# --- Main Conversion Execution ---

$iconPath = Join-Path $PSScriptRoot "icon.png"
$batchDir = Join-Path $env:TEMP "WebPConverter_Batch"
if (-not (Test-Path -LiteralPath $batchDir)) {
    New-Item -ItemType Directory -Path $batchDir -Force | Out-Null
}

if (-not $JobId) {
    $JobId = [Guid]::NewGuid().ToString('N')
}

$pendingFile = Join-Path $batchDir "$JobId.pending"
$doneFile = Join-Path $batchDir "$JobId.done"

# Ensure pending marker exists
if (-not (Test-Path -LiteralPath $pendingFile)) {
    try {
        [System.IO.File]::WriteAllText($pendingFile, "$FilePath")
    } catch {}
}

if (-not (Test-Path -LiteralPath $FilePath)) {
    # File not found
    Remove-Item -LiteralPath $pendingFile -Force -ErrorAction SilentlyContinue
    exit 1
}

$qualityLabel = switch ($Quality.ToLower()) {
    "lossless" { "Lossless" }
    "30"       { "30% (Low)" }
    "40"       { "40%" }
    "50"       { "50% (Medium)" }
    "60"       { "60%" }
    "70"       { "70% (Balanced/Web)" }
    "85"       { "85% (High)" }
    default    { "$Quality%" }
}

$magickExe = Find-MagickExecutable
if (-not $magickExe) {
    Remove-Item -LiteralPath $pendingFile -Force -ErrorAction SilentlyContinue
    $resultData = [PSCustomObject]@{
        JobId        = $JobId
        FilePath     = $FilePath
        BaseName     = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
        Success      = $false
        Quality      = $Quality
        QualityLabel = $qualityLabel
        OrigSize     = 0
        NewSize      = 0
        Error        = "ImageMagick was not found."
    }
    [System.IO.File]::WriteAllText($doneFile, ($resultData | ConvertTo-Json -Compress))
    Process-BatchToastNotification -BatchDir $batchDir -IconPath $iconPath
    exit 1
}

$fullPath = (Resolve-Path -LiteralPath $FilePath).Path
$dir = [System.IO.Path]::GetDirectoryName($fullPath)
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($fullPath)
$targetFile = [System.IO.Path]::Combine($dir, "$baseName.webp")
$tempFile = [System.IO.Path]::Combine($dir, "$baseName._tmp_$([Guid]::NewGuid().ToString('N')).webp")

$origSize = (Get-Item -LiteralPath $fullPath).Length

$magickArgs = @(
    $fullPath,
    "-auto-orient"
)

if ($Quality.ToLower() -eq "lossless") {
    $magickArgs += @("-define", "webp:lossless=true")
} else {
    $magickArgs += @("-quality", $Quality)
}

$magickArgs += $tempFile

$isSuccess = $false
$newSize = 0
$errorMsg = ""

try {
    $process = Start-Process -FilePath $magickExe -ArgumentList $magickArgs -Wait -NoNewWindow -PassThru

    if ($process.ExitCode -eq 0 -and (Test-Path -LiteralPath $tempFile)) {
        $newSize = (Get-Item -LiteralPath $tempFile).Length
        # Atomically overwrite destination file
        Move-Item -LiteralPath $tempFile -Destination $targetFile -Force
        $isSuccess = $true
    } else {
        if (Test-Path -LiteralPath $tempFile) {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
        $errorMsg = "Conversion process failed with exit code $($process.ExitCode)"
    }
}
catch {
    if (Test-Path -LiteralPath $tempFile) {
        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    }
    $errorMsg = $_.Exception.Message
}
finally {
    # 1. Remove pending marker
    Remove-Item -LiteralPath $pendingFile -Force -ErrorAction SilentlyContinue

    # 2. Write completion result
    $resultData = [PSCustomObject]@{
        JobId        = $JobId
        FilePath     = $fullPath
        BaseName     = $baseName
        Success      = $isSuccess
        Quality      = $Quality
        QualityLabel = $qualityLabel
        OrigSize     = $origSize
        NewSize      = $newSize
        Error        = $errorMsg
    }
    [System.IO.File]::WriteAllText($doneFile, ($resultData | ConvertTo-Json -Compress))

    # 3. Coordinate single toast notification
    Process-BatchToastNotification -BatchDir $batchDir -IconPath $iconPath
}

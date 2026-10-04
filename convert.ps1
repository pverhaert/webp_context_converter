#requires -Version 5.1
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$FilePath,

    [Parameter(Position = 1)]
    [string]$Quality = "70"
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
        if ($IconPath -and (Test-Path $IconPath)) {
            $imageUri = [System.Uri]::new($IconPath).AbsoluteUri
            $imageXml = "<image placement=""appLogoOverride"" src=""$imageUri"" hint-crop=""circle""/>"
        }

        # XML encode strings
        $safeTitle = [System.Security.SecurityElement]::Escape($Title)
        $safeMsg = [System.Security.SecurityElement]::Escape($Message)

        $template = @"
<toast>
    <visual>
        <binding template="ToastGeneric">
            <text>$safeTitle</text>
            <text>$safeMsg</text>
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

$iconPath = Join-Path $PSScriptRoot "icon.png"

if (-not (Test-Path -LiteralPath $FilePath)) {
    exit 1
}

$magickExe = Find-MagickExecutable
if (-not $magickExe) {
    Show-ToastNotification `
        -Title "WebP Conversion Error" `
        -Message "ImageMagick was not found. Please install ImageMagick." `
        -IconPath $iconPath
    exit 1
}

$fullPath = (Resolve-Path -LiteralPath $FilePath).Path
$dir = [System.IO.Path]::GetDirectoryName($fullPath)
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($fullPath)
$targetFile = [System.IO.Path]::Combine($dir, "$baseName.webp")
$tempFile = [System.IO.Path]::Combine($dir, "$baseName._tmp_$([Guid]::NewGuid().ToString('N')).webp")

$origSize = (Get-Item -LiteralPath $fullPath).Length

# Configure ImageMagick quality arguments
$qualityLabel = switch ($Quality.ToLower()) {
    "lossless" { "Lossless" }
    "30"       { "30% (Low)" }
    "40"       { "40%" }
    "50"       { "50% (Medium)" }
    "60"       { "60%" }
    "70"       { "70% (Balanced)" }
    "85"       { "85% (High)" }
    default    { "$Quality%" }
}

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

try {
    $process = Start-Process -FilePath $magickExe -ArgumentList $magickArgs -Wait -NoNewWindow -PassThru

    if ($process.ExitCode -eq 0 -and (Test-Path -LiteralPath $tempFile)) {
        $newSize = (Get-Item -LiteralPath $tempFile).Length
        
        # Atomically overwrite destination file
        Move-Item -LiteralPath $tempFile -Destination $targetFile -Force

        $origFmt = Format-FileSize $origSize
        $newFmt = Format-FileSize $newSize

        if ($origSize -gt 0) {
            $diff = $origSize - $newSize
            $pct = [Math]::Round(($diff / $origSize) * 100, 1)
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
            -Title "WebP Conversion Completed ($qualityLabel)" `
            -Message "$baseName.webp`n$statusText" `
            -IconPath $iconPath
    } else {
        if (Test-Path -LiteralPath $tempFile) {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
        Show-ToastNotification `
            -Title "WebP Conversion Failed" `
            -Message "Failed to convert $baseName.`nCheck if file format is supported and valid." `
            -IconPath $iconPath
    }
}
catch {
    if (Test-Path -LiteralPath $tempFile) {
        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    }
    Show-ToastNotification `
        -Title "WebP Conversion Error" `
        -Message "$($_.Exception.Message)" `
        -IconPath $iconPath
}

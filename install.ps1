#requires -Version 5.1
$ErrorActionPreference = "Stop"

$scriptDir = $PSScriptRoot
$iconPath = Join-Path $scriptDir "icon.ico"
$vbsPath = Join-Path $scriptDir "run_silent.vbs"

if (-not (Test-Path -LiteralPath $iconPath)) {
    Write-Error "Icon file not found: $iconPath"
}
if (-not (Test-Path -LiteralPath $vbsPath)) {
    Write-Error "VBS runner script not found: $vbsPath"
}

function Test-ImageMagickInstalled {
    if (Get-Command magick -ErrorAction SilentlyContinue) {
        return $true
    }

    $searchPaths = @(
        "$env:ProgramFiles\ImageMagick*",
        "${env:ProgramFiles(x86)}\ImageMagick*",
        "$env:LOCALAPPDATA\Programs\ImageMagick*"
    )
    foreach ($pattern in $searchPaths) {
        $dirs = Get-ChildItem -Path $pattern -Directory -ErrorAction SilentlyContinue
        foreach ($d in $dirs) {
            if (Test-Path -LiteralPath (Join-Path $d.FullName "magick.exe")) {
                return $true
            }
        }
    }
    return $false
}

function Refresh-EnvironmentPath {
    $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $env:PATH = "$machinePath;$userPath"
}

# Check and auto-install ImageMagick if missing
Write-Host "Checking ImageMagick installation..." -ForegroundColor Cyan

if (-not (Test-ImageMagickInstalled)) {
    Write-Host "ImageMagick is not installed on this system." -ForegroundColor Yellow
    Write-Host "Attempting automatic installation of ImageMagick..." -ForegroundColor Cyan

    $installed = $false

    # Method 1: Windows Package Manager (winget)
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        Write-Host "Installing ImageMagick via winget..." -ForegroundColor Cyan
        try {
            $proc = Start-Process -FilePath "winget" -ArgumentList "install --id ImageMagick.ImageMagick -e --accept-source-agreements --accept-package-agreements" -Wait -NoNewWindow -PassThru
            if ($proc.ExitCode -eq 0) {
                Refresh-EnvironmentPath
                if (Test-ImageMagickInstalled) {
                    $installed = $true
                    Write-Host "ImageMagick successfully installed via winget." -ForegroundColor Green
                }
            }
        } catch {
            Write-Warning "winget installation failed: $_"
        }
    }

    # Method 2: Fallback to Chocolatey if available
    if (-not $installed) {
        $chocoCmd = Get-Command choco -ErrorAction SilentlyContinue
        if ($chocoCmd) {
            Write-Host "Installing ImageMagick via chocolatey..." -ForegroundColor Cyan
            try {
                $proc = Start-Process -FilePath "choco" -ArgumentList "install imagemagick -y" -Wait -NoNewWindow -PassThru
                if ($proc.ExitCode -eq 0) {
                    Refresh-EnvironmentPath
                    if (Test-ImageMagickInstalled) {
                        $installed = $true
                        Write-Host "ImageMagick successfully installed via chocolatey." -ForegroundColor Green
                    }
                }
            } catch {
                Write-Warning "chocolatey installation failed: $_"
            }
        }
    }

    # Method 3: Direct official installer download fallback
    if (-not $installed) {
        Write-Host "Downloading ImageMagick installer directly..." -ForegroundColor Cyan
        $tempInstaller = Join-Path $env:TEMP "ImageMagick-installer.exe"
        $downloadUrl = "https://download.imagemagick.org/ImageMagick/download/binaries/ImageMagick-7.1.1-47-Q16-HDRI-x64-dll.exe"
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $downloadUrl -OutFile $tempInstaller -UseBasicParsing
            Write-Host "Running ImageMagick installer silently..." -ForegroundColor Cyan
            $proc = Start-Process -FilePath $tempInstaller -ArgumentList "/VERYSILENT /NORESTART /TASKS=""install_devel,install_Perl,associate,add_path""" -Wait -NoNewWindow -PassThru
            Remove-Item -LiteralPath $tempInstaller -Force -ErrorAction SilentlyContinue
            Refresh-EnvironmentPath
            if (Test-ImageMagickInstalled) {
                $installed = $true
                Write-Host "ImageMagick successfully installed." -ForegroundColor Green
            }
        } catch {
            Write-Warning "Direct installer download failed: $_"
        }
    }

    if (-not (Test-ImageMagickInstalled)) {
        Write-Error "Failed to install ImageMagick automatically. Please install ImageMagick manually from https://imagemagick.org."
    }
} else {
    Write-Host "ImageMagick is already installed." -ForegroundColor Green
}

$presets = @(
    @{ Key = "01_q30";      Label = "30% (Low)";              Param = "30" },
    @{ Key = "02_q40";      Label = "40%";                    Param = "40" },
    @{ Key = "03_q50";      Label = "50% (Medium)";           Param = "50" },
    @{ Key = "04_q60";      Label = "60%";                    Param = "60" },
    @{ Key = "05_q70";      Label = "70% (Balanced/Web)";     Param = "70" },
    @{ Key = "06_q85";      Label = "85% (High)";             Param = "85" },
    @{ Key = "07_lossless"; Label = "Lossless (100%)";        Param = "lossless" }
)

Write-Host "Configuring Windows Context Menu in registry..." -ForegroundColor Cyan

# 1. Clean up old entries
$anchorKey = "HKCU:\Software\Classes\SystemFileAssociations\image\shell\ConvertToWebP"
if (Test-Path -LiteralPath $anchorKey) {
    Remove-Item -LiteralPath $anchorKey -Recurse -Force
}

$subCommandsRelativePath = "SystemFileAssociations\image\ContextMenus\ConvertToWebP"
$subCommandsKey = "HKCU:\Software\Classes\$subCommandsRelativePath"

if (Test-Path -LiteralPath $subCommandsKey) {
    Remove-Item -LiteralPath $subCommandsKey -Recurse -Force
}

# Also cleanup wildcard path if it was created
$starSubCommandsKey = "HKCU:\Software\Classes\*\ContextMenus\ConvertToWebP"
if (Test-Path -LiteralPath $starSubCommandsKey) {
    Remove-Item -LiteralPath $starSubCommandsKey -Recurse -Force
}

# 2. Create Anchor Key
New-Item -Path $anchorKey -Force | Out-Null
Set-ItemProperty -LiteralPath $anchorKey -Name "(Default)" -Value "Convert to WebP"
Set-ItemProperty -LiteralPath $anchorKey -Name "MUIVerb" -Value "Convert to WebP"
Set-ItemProperty -LiteralPath $anchorKey -Name "Icon" -Value "$iconPath"
# ExtendedSubCommandsKey enables cascading submenu without CommandStore
Set-ItemProperty -LiteralPath $anchorKey -Name "ExtendedSubCommandsKey" -Value $subCommandsRelativePath

# 3. Create Submenu items
$shellKey = Join-Path $subCommandsKey "shell"
New-Item -Path $shellKey -Force | Out-Null

foreach ($p in $presets) {
    $itemKey = Join-Path $shellKey $p.Key
    New-Item -Path $itemKey -Force | Out-Null
    Set-ItemProperty -LiteralPath $itemKey -Name "(Default)" -Value $p.Label
    Set-ItemProperty -LiteralPath $itemKey -Name "MUIVerb" -Value $p.Label
    Set-ItemProperty -LiteralPath $itemKey -Name "Icon" -Value "$iconPath"

    $cmdKey = Join-Path $itemKey "command"
    New-Item -Path $cmdKey -Force | Out-Null
    $cmdString = "wscript.exe `"$vbsPath`" `"%1`" `"$($p.Param)`""
    Set-ItemProperty -LiteralPath $cmdKey -Name "(Default)" -Value $cmdString
}

# Also mirror under *\ContextMenus\ConvertToWebP for maximum Explorer compatibility
$starShellKey = Join-Path $starSubCommandsKey "shell"
New-Item -Path $starShellKey -Force | Out-Null

foreach ($p in $presets) {
    $itemKey = Join-Path $starShellKey $p.Key
    New-Item -Path $itemKey -Force | Out-Null
    Set-ItemProperty -LiteralPath $itemKey -Name "(Default)" -Value $p.Label
    Set-ItemProperty -LiteralPath $itemKey -Name "MUIVerb" -Value $p.Label
    Set-ItemProperty -LiteralPath $itemKey -Name "Icon" -Value "$iconPath"

    $cmdKey = Join-Path $itemKey "command"
    New-Item -Path $cmdKey -Force | Out-Null
    $cmdString = "wscript.exe `"$vbsPath`" `"%1`" `"$($p.Param)`""
    Set-ItemProperty -LiteralPath $cmdKey -Name "(Default)" -Value $cmdString
}

Write-Host ""
Write-Host "Installation completed successfully!" -ForegroundColor Green
Write-Host "The cascading submenu under 'Convert to WebP' is now active." -ForegroundColor Yellow
Write-Host "Tip: Shift + Right-click directly opens the classic menu on Windows 11 (or click 'Show more options')." -ForegroundColor Yellow


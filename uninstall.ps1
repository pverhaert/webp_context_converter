#requires -Version 5.1
$ErrorActionPreference = "SilentlyContinue"

Write-Host "Removing 'Convert to WebP' context menu from Windows Registry..." -ForegroundColor Cyan

$keysToRemove = @(
    "HKCU:\Software\Classes\SystemFileAssociations\image\shell\ConvertToWebP",
    "HKCU:\Software\Classes\SystemFileAssociations\image\ContextMenus\ConvertToWebP",
    "HKCU:\Software\Classes\*\ContextMenus\ConvertToWebP"
)

$removedAny = $false
foreach ($key in $keysToRemove) {
    if (Test-Path -LiteralPath $key) {
        Remove-Item -LiteralPath $key -Recurse -Force
        $removedAny = $true
    }
}

if ($removedAny) {
    Write-Host "Context menu successfully removed." -ForegroundColor Green
} else {
    Write-Host "Context menu was not found or is already removed." -ForegroundColor Yellow
}

Write-Host "Note: ImageMagick has been retained on your system and was not removed." -ForegroundColor Cyan

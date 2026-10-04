# WebP Windows Context Menu Converter

A fast, lightweight, and elegant context menu extension for Windows 10 & 11 to convert images directly to WebP via right-click using ImageMagick.

![WebP Icon](icon.png)

## Features
- **Context Menu Integration**: Supports all common image formats (PNG, JPG, JPEG, WEBP, GIF, BMP, TIFF, AVIF, etc.).
- **Submenu Quality Presets**:
  - `30% (Low)`
  - `40%`
  - `50% (Medium)`
  - `60%`
  - `70% (Balanced/Web)`
  - `85% (High)`
  - `Lossless (100%)` (lossless WebP encoding via `-define webp:lossless=true`)
- **Completely Silent**: Zero flickering terminal or PowerShell pop-up windows, powered by a silent VBS launcher.
- **Native Windows Toast Notifications**: Displays clean notification cards showing saved percentage (e.g., `-78%`) or error details.
- **Preserves Original Files**: Saves the `.webp` image in the same directory under the same base name.
- **Atomic Overwrites**: Safely overwrites target `.webp` files when re-converting or compressing an existing `.webp` file.
- **Automatic Dependency Setup**: Automatically detects and installs ImageMagick (via `winget` or direct download) if missing.
- **Safe Uninstallation**: Uninstalling removes only the context menu entries—ImageMagick is **never** uninstalled or removed.
- **No Administrator Privileges Required**: Installs directly under `HKEY_CURRENT_USER`.

## Requirements
- **Windows 10 or Windows 11**
- **ImageMagick** (automatically installed by `install.bat` / `install.ps1` if not already installed).

## Installation
Simply double-click:
```cmd
install.bat
```
*(Or execute `powershell -ExecutionPolicy Bypass -File install.ps1` in PowerShell.)*

## Usage
1. **Shift + Right-click** on any image file (or regular right-click and select **Show more options**).
2. Hover over **Convert to WebP**.
3. Select your desired compression preset (e.g., **70% (Balanced/Web)**).
4. The converted `.webp` file will appear in the same folder, accompanied by a Windows notification showing the size reduction.

## Uninstallation
Simply double-click:
```cmd
uninstall.bat
```
*(Or execute `powershell -ExecutionPolicy Bypass -File uninstall.ps1` in PowerShell.)*
> **Note**: Uninstallation only unregisters the context menu from Windows Explorer. ImageMagick is retained on your system.

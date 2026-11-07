# Captures a PNG of every open game window (works even when windows overlap or sit on
# another monitor) and prints each window's process id, position and file path.
# Windows are ordered by process start time, so with tools/run_local.ps1 index 0 is the host.
#
# Usage: .\.claude\skills\run-game\scripts\capture_windows.ps1 [-OutDir <dir>] [-Prefix win]

param(
    [string]$OutDir = (Join-Path ([System.IO.Path]::GetTempPath()) "kftm_windows"),
    [string]$Prefix = "win",
    [string]$TitleLike = "Adrift*"
)

Add-Type -AssemblyName System.Drawing
if (-not ("KftmCapture" -as [type])) {
    Add-Type @"
using System; using System.Runtime.InteropServices;
public static class KftmCapture {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
}
# Without this, rects and bitmaps are scaled on monitors with display scaling.
[KftmCapture]::SetProcessDPIAware() | Out-Null

New-Item -ItemType Directory -Force $OutDir | Out-Null
$windows = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like $TitleLike } | Sort-Object StartTime
if (-not $windows) {
    Write-Host "No windows titled '$TitleLike' are open."
    exit 1
}

$index = 0
foreach ($proc in $windows) {
    $rect = New-Object KftmCapture+RECT
    [KftmCapture]::GetWindowRect($proc.MainWindowHandle, [ref]$rect) | Out-Null
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top

    $bitmap = New-Object System.Drawing.Bitmap $width, $height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $hdc = $graphics.GetHdc()
    # Flag 2 = PW_RENDERFULLCONTENT, needed to capture Vulkan/D3D-rendered content.
    [KftmCapture]::PrintWindow($proc.MainWindowHandle, $hdc, 2) | Out-Null
    $graphics.ReleaseHdc($hdc)
    $graphics.Dispose()

    $file = Join-Path $OutDir "$Prefix$index.png"
    $bitmap.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()

    Write-Host ("{0}{1}  pid={2}  at=({3},{4})  {5}x{6}  {7}" -f $Prefix, $index, $proc.Id, $rect.Left, $rect.Top, $width, $height, $file)
    $index++
}
exit 0

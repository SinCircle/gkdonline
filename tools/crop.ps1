# 把截图里的某块区域裁剪并放大，用于肉眼核对细节（居中对齐、圆角、颜色这类）。
# 本机没有 Python 的 PIL，所以这步用 .NET 的 System.Drawing。
#
# 用法：
#   pwsh -NoProfile -File tools/crop.ps1 -Source verification/x/screen.jpeg `
#        -Target verification/x/crop.png -Box 40,360,200,170 -Scale 4
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)][string]$Box,   # x,y,w,h，原图像素坐标
    [int]$Scale = 4
)
Add-Type -AssemblyName System.Drawing

$parts = $Box.Split(',')
if ($parts.Count -ne 4) { Write-Error "Box 需要 x,y,w,h 四个数字"; exit 1 }
$rect = New-Object System.Drawing.Rectangle([int]$parts[0], [int]$parts[1], [int]$parts[2], [int]$parts[3])

$image = [System.Drawing.Image]::FromFile((Resolve-Path $Source))
$bitmap = New-Object System.Drawing.Bitmap(($rect.Width * $Scale), ($rect.Height * $Scale))
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.InterpolationMode = 'NearestNeighbor'
$destination = New-Object System.Drawing.Rectangle(0, 0, ($rect.Width * $Scale), ($rect.Height * $Scale))
$graphics.DrawImage($image, $destination, $rect, 'Pixel')
$bitmap.Save((Join-Path (Get-Location) $Target), 'Png')
$graphics.Dispose(); $bitmap.Dispose(); $image.Dispose()

Write-Output "cropped $Box x$Scale -> $Target"

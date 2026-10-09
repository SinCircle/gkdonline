Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$srcPath = Join-Path $PSScriptRoot "icon-source.png"
$src = [System.Drawing.Bitmap]::FromFile($srcPath)
$W = $src.Width; $H = $src.Height

# 线稿在图里的实际范围（上一轮量出来的）
$sx = 16; $sy = 25; $sw = 111; $sh = 89
$INK_R = 0x9F; $INK_G = 0x12; $INK_B = 0x14

# 原图是「白底 + 纯色线稿」。绿通道动态范围最大（白 255 / 线 0x12），
# 用它反推覆盖度：c = (255 - G) / (255 - 0x12)，纯线处正好 255、白底正好 0。
$inkMin = [Math]::Min($INK_R, [Math]::Min($INK_G, $INK_B))

# 中间图：RGB 统一填线色，A 存覆盖度。这样双三次插值时颜色处处相同，
# 只有 alpha 变化，不会在边缘出现黑边/彩边。
$mid = New-Object System.Drawing.Bitmap($W, $H, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$rect = New-Object System.Drawing.Rectangle -ArgumentList 0, 0, $W, $H
$data = $mid.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly,
  [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$bytes = New-Object byte[] ($data.Stride * $H)
for ($y = 0; $y -lt $H; $y++) {
  for ($x = 0; $x -lt $W; $x++) {
    $c = $src.GetPixel($x, $y)
    $ink = [Math]::Round((255 - $c.G) * 255.0 / (255 - $inkMin))
    if ($ink -lt 0) { $ink = 0 } elseif ($ink -gt 255) { $ink = 255 }
    $o = $y * $data.Stride + $x * 4
    $bytes[$o] = $INK_B; $bytes[$o + 1] = $INK_G; $bytes[$o + 2] = $INK_R; $bytes[$o + 3] = $ink
  }
}
[System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $data.Scan0, $bytes.Length)
$mid.UnlockBits($data)
$src.Dispose()

function Draw-Logo($canvas, $logoW, $logoH) {
  $g = [System.Drawing.Graphics]::FromImage($canvas)
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $ia = New-Object System.Drawing.Imaging.ImageAttributes
  $ia.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
  $dst = New-Object System.Drawing.Rectangle -ArgumentList ([int](($canvas.Width - $logoW) / 2)),
    ([int](($canvas.Height - $logoH) / 2)), $logoW, $logoH
  $g.DrawImage($mid, $dst, $sx, $sy, $sw, $sh, [System.Drawing.GraphicsUnit]::Pixel, $ia)
  $ia.Dispose(); $g.Dispose()
}

function New-Canvas($w, $h, $bg) {
  $b = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($b)
  if ($bg -eq 'clear') { $g.Clear([System.Drawing.Color]::Transparent) }
  else { $g.Clear([System.Drawing.Color]::FromArgb(255, 255, 255, 255)) }
  $g.Dispose()
  return $b
}

# 前景：1024 画布，线稿宽占 68%。
# 45% 是按原来的方形字形定的，换成这个扁长的校徽后显得小一圈（启动器上比 设置/文件管理 都小），
# 而且校徽是细线勾勒、墨量本来就少，要放大一些才和系统图标的视觉重量相当。
$fg = New-Canvas 1024 1024 'clear'
Draw-Logo $fg ([int](1024 * 0.68)) ([int](1024 * 0.68 * $sh / $sw))
$fg.Save("$root\entry\src\main\resources\base\media\foreground.png", [System.Drawing.Imaging.ImageFormat]::Png)
$fg.Save("$root\AppScope\resources\base\media\foreground.png", [System.Drawing.Imaging.ImageFormat]::Png)

# 背景：1024 纯白
$bg = New-Canvas 1024 1024 'white'
$bg.Save("$root\entry\src\main\resources\base\media\background.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bg.Save("$root\AppScope\resources\base\media\background.png", [System.Drawing.Imaging.ImageFormat]::Png)

# 启动图标记：256 画布，线稿占满宽度的 96%
# （原 splashMark 的内容铺满整张 256 画布，这里跟着取大，免得启动图看着比原来小一圈）
$sm = New-Canvas 256 256 'clear'
Draw-Logo $sm ([int](256 * 0.96)) ([int](256 * 0.96 * $sh / $sw))
$sm.Save("$root\entry\src\main\resources\base\media\splashMark.png", [System.Drawing.Imaging.ImageFormat]::Png)

# 校验：读出结果的内容 bbox
foreach ($p in @("$root\entry\src\main\resources\base\media\foreground.png",
                 "$root\entry\src\main\resources\base\media\splashMark.png")) {
  $b = [System.Drawing.Bitmap]::FromFile($p)
  $minX = $b.Width; $minY = $b.Height; $maxX = -1; $maxY = -1
  for ($y = 0; $y -lt $b.Height; $y++) {
    for ($x = 0; $x -lt $b.Width; $x++) {
      if ($b.GetPixel($x, $y).A -gt 16) {
        if ($x -lt $minX) { $minX = $x }; if ($x -gt $maxX) { $maxX = $x }
        if ($y -lt $minY) { $minY = $y }; if ($y -gt $maxY) { $maxY = $y }
      }
    }
  }
  $c = $b.GetPixel([int](($minX + $maxX) / 2), [int](($minY + $maxY) / 2))
  Write-Output ("{0,-16} {1}x{2}  bbox=[{3},{4}]-[{5},{6}]  占宽 {7:P1} 占高 {8:P1}  中心色 #{9:X2}{10:X2}{11:X2} A{12}" -f `
    (Split-Path $p -Leaf), $b.Width, $b.Height, $minX, $minY, $maxX, $maxY,
    (($maxX - $minX + 1) / $b.Width), (($maxY - $minY + 1) / $b.Height), $c.R, $c.G, $c.B, $c.A)
  $b.Dispose()
}
$mid.Dispose(); $fg.Dispose(); $bg.Dispose(); $sm.Dispose()
Write-Output "图标生成完成"

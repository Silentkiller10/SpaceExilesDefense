param(
    [string]$SrcDir,
    [string]$OutPath
)
Add-Type -AssemblyName System.Drawing

# Natural sort by the number in "Layer N.png"
$files = Get-ChildItem $SrcDir -Filter "*.png" | Where-Object { $_.Name -notlike "*.import" } |
    Sort-Object { [int]($_.BaseName -replace '\D', '') }
if ($files.Count -lt 2) { Write-Output "ERROR: no frames found"; exit 1 }

# Measure opaque bounding box of each frame
$frames = @()
$maxW = 0; $maxH = 0
foreach ($f in $files) {
    $bmp = [System.Drawing.Bitmap]::FromFile($f.FullName)
    $w = $bmp.Width; $h = $bmp.Height
    $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
    $data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $bytes = New-Object byte[] ($data.Stride * $h)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)
    $minX = $w; $maxX = -1; $minY = $h; $maxY = -1
    for ($y = 0; $y -lt $h; $y++) {
        $row = $y * $data.Stride
        for ($x = 0; $x -lt $w; $x++) {
            if ($bytes[$row + $x * 4 + 3] -gt 24) {
                if ($x -lt $minX) { $minX = $x }
                if ($x -gt $maxX) { $maxX = $x }
                if ($y -lt $minY) { $minY = $y }
                if ($y -gt $maxY) { $maxY = $y }
            }
        }
    }
    $bmp.UnlockBits($data)
    $bw = $maxX - $minX + 1; $bh = $maxY - $minY + 1
    if ($bw -gt $maxW) { $maxW = $bw }
    if ($bh -gt $maxH) { $maxH = $bh }
    $frames += ,@{ bmp = $bmp; x = $minX; y = $minY; w = $bw; h = $bh; name = $f.Name }
}

$cellW = $maxW + 6; $cellH = $maxH + 4
$outBmp = New-Object System.Drawing.Bitmap(($cellW * $frames.Count), $cellH, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$og = [System.Drawing.Graphics]::FromImage($outBmp)
$og.Clear([System.Drawing.Color]::Transparent)
for ($i = 0; $i -lt $frames.Count; $i++) {
    $fr = $frames[$i]
    $destX = $i * $cellW + [int](($cellW - $fr.w) / 2)
    $destY = $cellH - 2 - $fr.h   # feet bottom-aligned
    $destRect = New-Object System.Drawing.Rectangle($destX, $destY, $fr.w, $fr.h)
    $srcRect = New-Object System.Drawing.Rectangle($fr.x, $fr.y, $fr.w, $fr.h)
    $og.DrawImage($fr.bmp, $destRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
    $fr.bmp.Dispose()
}
$og.Dispose()
$outBmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
$outBmp.Dispose()
Write-Output "saved: $OutPath  cell=${cellW}x${cellH}  frames=$($frames.Count)"
Write-Output ("order: " + (($files | ForEach-Object { $_.BaseName }) -join ", "))

param(
    [string]$SrcPath,
    [string]$OutPath,
    [int]$Threshold = 16
)
Add-Type -AssemblyName System.Drawing

# Flood-fill background removal: only near-black pixels connected to the image
# border become transparent; dark pixels inside the art stay opaque.
$src = [System.Drawing.Bitmap]::FromFile($SrcPath)
$w = $src.Width; $h = $src.Height
$total = $w * $h
$bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.DrawImage($src, 0, 0, $w, $h)
$g.Dispose(); $src.Dispose()

$rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
$data = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadWrite, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$stride = $data.Stride
$bytes = New-Object byte[] ($stride * $h)
[System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $bytes.Length)

$isDark = New-Object bool[] $total
for ($y = 0; $y -lt $h; $y++) {
    $row = $y * $stride; $base = $y * $w
    for ($x = 0; $x -lt $w; $x++) {
        $i = $row + $x * 4
        $m = $bytes[$i]
        if ($bytes[$i + 1] -gt $m) { $m = $bytes[$i + 1] }
        if ($bytes[$i + 2] -gt $m) { $m = $bytes[$i + 2] }
        if ($m -le $Threshold) { $isDark[$base + $x] = $true }
    }
}

$isBg = New-Object bool[] $total
$queue = New-Object 'System.Collections.Generic.Queue[int]'
for ($x = 0; $x -lt $w; $x++) {
    foreach ($idx in @($x, (($h - 1) * $w + $x))) {
        if ($isDark[$idx] -and -not $isBg[$idx]) { $isBg[$idx] = $true; $queue.Enqueue($idx) }
    }
}
for ($y = 0; $y -lt $h; $y++) {
    foreach ($idx in @(($y * $w), ($y * $w + $w - 1))) {
        if ($isDark[$idx] -and -not $isBg[$idx]) { $isBg[$idx] = $true; $queue.Enqueue($idx) }
    }
}
while ($queue.Count -gt 0) {
    $idx = $queue.Dequeue()
    $cy = [int][math]::Floor($idx / $w); $cx = $idx - $cy * $w
    if ($cx -gt 0) { $n = $idx - 1; if ($isDark[$n] -and -not $isBg[$n]) { $isBg[$n] = $true; $queue.Enqueue($n) } }
    if ($cx -lt ($w - 1)) { $n = $idx + 1; if ($isDark[$n] -and -not $isBg[$n]) { $isBg[$n] = $true; $queue.Enqueue($n) } }
    if ($cy -gt 0) { $n = $idx - $w; if ($isDark[$n] -and -not $isBg[$n]) { $isBg[$n] = $true; $queue.Enqueue($n) } }
    if ($cy -lt ($h - 1)) { $n = $idx + $w; if ($isDark[$n] -and -not $isBg[$n]) { $isBg[$n] = $true; $queue.Enqueue($n) } }
}

$cleared = 0
for ($y = 0; $y -lt $h; $y++) {
    $row = $y * $stride; $base = $y * $w
    for ($x = 0; $x -lt $w; $x++) {
        if ($isBg[$base + $x]) { $bytes[$row + $x * 4 + 3] = 0; $cleared++ }
    }
}
[System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $data.Scan0, $bytes.Length)
$bmp.UnlockBits($data)
$bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "saved: $OutPath  cleared=$cleared of $total px"

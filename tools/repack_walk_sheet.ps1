param(
    [string]$SrcPath,
    [string]$OutPath
)
Add-Type -AssemblyName System.Drawing

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

# --- Step 1: dark mask (background is black + JPEG noise; character interior can also be dark) ---
$bgThreshold = 16
$isDark = New-Object bool[] $total
for ($y = 0; $y -lt $h; $y++) {
    $row = $y * $stride; $base = $y * $w
    for ($x = 0; $x -lt $w; $x++) {
        $i = $row + $x * 4
        $m = $bytes[$i]
        if ($bytes[$i + 1] -gt $m) { $m = $bytes[$i + 1] }
        if ($bytes[$i + 2] -gt $m) { $m = $bytes[$i + 2] }
        if ($m -le $bgThreshold) { $isDark[$base + $x] = $true }
    }
}

# --- Step 2: flood fill background from image borders through dark pixels ---
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

# --- Step 3: kill small opaque noise islands (JPEG specks floating in the gaps) ---
$minIsland = 40
$seen = New-Object bool[] $total
$stack = New-Object 'System.Collections.Generic.Stack[int]'
for ($s = 0; $s -lt $total; $s++) {
    if ($isBg[$s] -or $seen[$s]) { continue }
    $comp = New-Object 'System.Collections.Generic.List[int]'
    $stack.Push($s); $seen[$s] = $true
    while ($stack.Count -gt 0) {
        $idx = $stack.Pop(); $comp.Add($idx)
        $cy = [int][math]::Floor($idx / $w); $cx = $idx - $cy * $w
        if ($cx -gt 0) { $n = $idx - 1; if (-not $isBg[$n] -and -not $seen[$n]) { $seen[$n] = $true; $stack.Push($n) } }
        if ($cx -lt ($w - 1)) { $n = $idx + 1; if (-not $isBg[$n] -and -not $seen[$n]) { $seen[$n] = $true; $stack.Push($n) } }
        if ($cy -gt 0) { $n = $idx - $w; if (-not $isBg[$n] -and -not $seen[$n]) { $seen[$n] = $true; $stack.Push($n) } }
        if ($cy -lt ($h - 1)) { $n = $idx + $w; if (-not $isBg[$n] -and -not $seen[$n]) { $seen[$n] = $true; $stack.Push($n) } }
    }
    if ($comp.Count -lt $minIsland) {
        foreach ($idx in $comp) { $isBg[$idx] = $true }
    }
}

# --- Step 4: re-fill interior holes (transparent regions not connected to the border) ---
$reach = New-Object bool[] $total
$queue.Clear()
for ($x = 0; $x -lt $w; $x++) {
    foreach ($idx in @($x, (($h - 1) * $w + $x))) {
        if ($isBg[$idx] -and -not $reach[$idx]) { $reach[$idx] = $true; $queue.Enqueue($idx) }
    }
}
for ($y = 0; $y -lt $h; $y++) {
    foreach ($idx in @(($y * $w), ($y * $w + $w - 1))) {
        if ($isBg[$idx] -and -not $reach[$idx]) { $reach[$idx] = $true; $queue.Enqueue($idx) }
    }
}
while ($queue.Count -gt 0) {
    $idx = $queue.Dequeue()
    $cy = [int][math]::Floor($idx / $w); $cx = $idx - $cy * $w
    if ($cx -gt 0) { $n = $idx - 1; if ($isBg[$n] -and -not $reach[$n]) { $reach[$n] = $true; $queue.Enqueue($n) } }
    if ($cx -lt ($w - 1)) { $n = $idx + 1; if ($isBg[$n] -and -not $reach[$n]) { $reach[$n] = $true; $queue.Enqueue($n) } }
    if ($cy -gt 0) { $n = $idx - $w; if ($isBg[$n] -and -not $reach[$n]) { $reach[$n] = $true; $queue.Enqueue($n) } }
    if ($cy -lt ($h - 1)) { $n = $idx + $w; if ($isBg[$n] -and -not $reach[$n]) { $reach[$n] = $true; $queue.Enqueue($n) } }
}
for ($i = 0; $i -lt $total; $i++) {
    if ($isBg[$i] -and -not $reach[$i]) { $isBg[$i] = $false }  # interior hole -> opaque
}

# --- Step 4.5: morphological closing (dilate 3, erode 3) — fills dark shading gaps
# the flood fill carved out of the character, while preserving the silhouette ---
$origSolid = New-Object bool[] $total
for ($i = 0; $i -lt $total; $i++) { $origSolid[$i] = -not $isBg[$i] }
$radius = 3
for ($pass = 0; $pass -lt $radius; $pass++) {
    $grow = New-Object 'System.Collections.Generic.List[int]'
    for ($y = 0; $y -lt $h; $y++) {
        $base = $y * $w
        for ($x = 0; $x -lt $w; $x++) {
            $idx = $base + $x
            if (-not $isBg[$idx]) { continue }
            if (($x -gt 0 -and -not $isBg[$idx - 1]) -or ($x -lt ($w - 1) -and -not $isBg[$idx + 1]) -or ($y -gt 0 -and -not $isBg[$idx - $w]) -or ($y -lt ($h - 1) -and -not $isBg[$idx + $w])) {
                $grow.Add($idx)
            }
        }
    }
    foreach ($idx in $grow) { $isBg[$idx] = $false }
}
for ($pass = 0; $pass -lt $radius; $pass++) {
    $shrink = New-Object 'System.Collections.Generic.List[int]'
    for ($y = 0; $y -lt $h; $y++) {
        $base = $y * $w
        for ($x = 0; $x -lt $w; $x++) {
            $idx = $base + $x
            if ($isBg[$idx] -or $origSolid[$idx]) { continue }
            if (($x -eq 0) -or ($x -eq ($w - 1)) -or ($y -eq 0) -or ($y -eq ($h - 1)) -or $isBg[$idx - 1] -or $isBg[$idx + 1] -or $isBg[$idx - $w] -or $isBg[$idx + $w]) {
                $shrink.Add($idx)
            }
        }
    }
    foreach ($idx in $shrink) { $isBg[$idx] = $true }
}

# --- Apply alpha ---
for ($y = 0; $y -lt $h; $y++) {
    $row = $y * $stride; $base = $y * $w
    for ($x = 0; $x -lt $w; $x++) {
        if ($isBg[$base + $x]) { $bytes[$row + $x * 4 + 3] = 0 } else { $bytes[$row + $x * 4 + 3] = 255 }
    }
}
[System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $data.Scan0, $bytes.Length)
$bmp.UnlockBits($data)

# --- Step 5: frame segmentation on column occupancy ---
$occ = New-Object bool[] $w
for ($x = 0; $x -lt $w; $x++) {
    $count = 0
    for ($y = 0; $y -lt $h; $y++) {
        if (-not $isBg[$y * $w + $x]) { $count++; if ($count -ge 3) { $occ[$x] = $true; break } }
    }
}
$segments = @()
$start = -1; $lastOcc = -10
for ($x = 0; $x -lt $w; $x++) {
    if ($occ[$x]) {
        if ($start -lt 0) { $start = $x }
        $lastOcc = $x
    } elseif ($start -ge 0 -and ($x - $lastOcc) -gt 2) {
        if (($lastOcc - $start) -ge 25) { $segments += ,@($start, $lastOcc) }
        $start = -1
    }
}
if ($start -ge 0 -and ($lastOcc - $start) -ge 25) { $segments += ,@($start, $lastOcc) }

# Iteratively split merged segments at their emptiest column until all are ~1 frame wide.
# Median of the narrow (clean) segments approximates the true frame pitch.
$colCount = New-Object int[] $w
for ($x = 0; $x -lt $w; $x++) {
    $count = 0
    for ($y = 0; $y -lt $h; $y++) { if (-not $isBg[$y * $w + $x]) { $count++ } }
    $colCount[$x] = $count
}
$widths = $segments | ForEach-Object { $_[1] - $_[0] + 1 } | Sort-Object
$median = $widths[[int]($widths.Count / 2)]
$work = New-Object 'System.Collections.Generic.Stack[object]'
foreach ($seg in $segments) { $work.Push($seg) }
$final = @()
while ($work.Count -gt 0) {
    $seg = $work.Pop()
    $sw = $seg[1] - $seg[0] + 1
    if ($sw -le ($median * 1.45)) { $final += ,$seg; continue }
    # Likely N merged frames: cut near the first expected boundary (one pitch in)
    $target = $seg[0] + $median
    $lo = [math]::Max($seg[0] + 25, $target - 18)
    $hi = [math]::Min($seg[1] - 25, $target + 18)
    $bestX = $target; $bestCount = [int]::MaxValue
    for ($x = $lo; $x -le $hi; $x++) {
        if ($colCount[$x] -lt $bestCount) { $bestCount = $colCount[$x]; $bestX = $x }
    }
    $work.Push(@($seg[0], ($bestX - 1)))
    $work.Push(@(($bestX + 1), $seg[1]))
}
$segments = $final | Sort-Object { $_[0] }

Write-Output "frames detected: $($segments.Count)"
$segments | ForEach-Object { Write-Output ("  x {0}-{1} (w={2})" -f $_[0], $_[1], ($_[1] - $_[0] + 1)) }
if ($segments.Count -lt 2) { Write-Output "ERROR: segmentation failed"; exit 1 }

# --- Step 6: per-frame bounds, repack into uniform bottom-aligned cells ---
$boxes = @()
$maxW = 0; $maxH = 0
foreach ($seg in $segments) {
    $minY = $h; $maxY = -1
    for ($y = 0; $y -lt $h; $y++) {
        $base = $y * $w
        for ($x = $seg[0]; $x -le $seg[1]; $x++) {
            if (-not $isBg[$base + $x]) {
                if ($y -lt $minY) { $minY = $y }
                if ($y -gt $maxY) { $maxY = $y }
                break
            }
        }
    }
    $bw = $seg[1] - $seg[0] + 1; $bh = $maxY - $minY + 1
    if ($bw -gt $maxW) { $maxW = $bw }
    if ($bh -gt $maxH) { $maxH = $bh }
    $boxes += ,@($seg[0], $minY, $bw, $bh)
}

$cellW = $maxW + 6; $cellH = $maxH + 4
$outBmp = New-Object System.Drawing.Bitmap(($cellW * $boxes.Count), $cellH, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$og = [System.Drawing.Graphics]::FromImage($outBmp)
$og.Clear([System.Drawing.Color]::Transparent)
for ($i = 0; $i -lt $boxes.Count; $i++) {
    $bx = $boxes[$i]
    $destX = $i * $cellW + [int](($cellW - $bx[2]) / 2)
    $destY = $cellH - 2 - $bx[3]
    $destRect = New-Object System.Drawing.Rectangle($destX, $destY, $bx[2], $bx[3])
    $srcRect = New-Object System.Drawing.Rectangle($bx[0], $bx[1], $bx[2], $bx[3])
    $og.DrawImage($bmp, $destRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
}
$og.Dispose(); $bmp.Dispose()
$outBmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
$outBmp.Dispose()
Write-Output "saved: $OutPath  cell=${cellW}x${cellH}  frames=$($boxes.Count)"

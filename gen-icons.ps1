Add-Type -AssemblyName System.Drawing

# 3-2-1 app icon: dark ground + three growing amber bars (the "words get
# longer" mark). Bars share a left edge; the bounding box is centred.

function Add-RoundRect {
    param(
        [System.Drawing.Drawing2D.GraphicsPath]$Path,
        [double]$X, [double]$Y, [double]$W, [double]$H, [double]$R
    )
    $rr = [Math]::Min($R, [Math]::Min($W, $H) / 2.0)
    $d = 2.0 * $rr
    $Path.AddArc($X, $Y, $d, $d, 180, 90)
    $Path.AddArc($X + $W - $d, $Y, $d, $d, 270, 90)
    $Path.AddArc($X + $W - $d, $Y + $H - $d, $d, $d, 0, 90)
    $Path.AddArc($X, $Y + $H - $d, $d, $d, 90, 90)
    $Path.CloseFigure()
}

function New-Icon {
    param([int]$Size, [double]$PadX, [string]$OutPath, [switch]$Maskable)

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    $bg = [System.Drawing.Color]::FromArgb(28, 25, 23)       # #1c1917
    $accent = [System.Drawing.Color]::FromArgb(245, 158, 11) # #f59e0b
    $bgBrush = New-Object System.Drawing.SolidBrush($bg)

    if ($Maskable) {
        $g.FillRectangle($bgBrush, 0, 0, $Size, $Size)
    } else {
        $p = New-Object System.Drawing.Drawing2D.GraphicsPath
        Add-RoundRect -Path $p -X 0 -Y 0 -W $Size -H $Size -R ($Size * 0.18)
        $g.FillPath($bgBrush, $p)
        $p.Dispose()
    }

    [double]$cw = $Size - ($Size * 2.0 * $PadX)
    [double]$bh = $cw * 0.19
    [double]$gap = $bh * 0.5
    [double]$stackH = (3.0 * $bh) + (2.0 * $gap)
    [double]$leftX = ($Size - $cw) / 2.0
    [double]$startY = ($Size - $stackH) / 2.0
    [double]$br = $bh * 0.42
    $w1 = $cw * 0.40
    $w2 = $cw * 0.70
    $w3 = $cw

    $accBrush = New-Object System.Drawing.SolidBrush($accent)
    $rows = @(
        @{ y = $startY;                     w = $w1 },
        @{ y = $startY + ($bh + $gap);       w = $w2 },
        @{ y = $startY + (2.0 * ($bh + $gap)); w = $w3 }
    )
    foreach ($row in $rows) {
        $bp = New-Object System.Drawing.Drawing2D.GraphicsPath
        Add-RoundRect -Path $bp -X $leftX -Y $row.y -W $row.w -H $bh -R $br
        $g.FillPath($accBrush, $bp)
        $bp.Dispose()
    }

    $g.Dispose()
    $bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "wrote $OutPath"
}

$dir = "D:\Claude Code\portfolio\games\3-2-1"
New-Icon -Size 192 -PadX 0.18 -OutPath "$dir\icon-192.png"
New-Icon -Size 512 -PadX 0.18 -OutPath "$dir\icon-512.png"
New-Icon -Size 512 -PadX 0.28 -OutPath "$dir\icon-maskable-512.png" -Maskable

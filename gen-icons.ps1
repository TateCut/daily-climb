Add-Type -AssemblyName System.Drawing

# Wadder app icon: dark ground + the ladder mark — two rails, six rungs, the top
# rung spanning both rails (one word climbed) and each rung below it a step
# shorter. Drawn from the same 48x120 viewBox as the in-app brandmark.

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

function Blend {
    param([System.Drawing.Color]$C1, [System.Drawing.Color]$C2, [double]$T)
    $rr = [int][Math]::Round($C1.R * (1 - $T) + $C2.R * $T)
    $gg = [int][Math]::Round($C1.G * (1 - $T) + $C2.G * $T)
    $bb = [int][Math]::Round($C1.B * (1 - $T) + $C2.B * $T)
    return [System.Drawing.Color]::FromArgb([int]$rr, [int]$gg, [int]$bb)
}

function New-Icon {
    param([int]$Size, [double]$LadderFrac, [string]$OutPath, [switch]$Maskable)

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    $bg = [System.Drawing.Color]::FromArgb(28, 25, 23)        # #1c1917
    $accent = [System.Drawing.Color]::FromArgb(245, 158, 11)  # #f59e0b
    $white = [System.Drawing.Color]::FromArgb(255, 255, 255)
    $dim = Blend $accent $bg 0.38                             # dimmed rung
    $lite = Blend $accent $white 0.34                         # rung highlight
    $bolt = Blend $accent $bg 0.16                            # bolt heads

    $bgBrush = New-Object System.Drawing.SolidBrush($bg)
    if ($Maskable) {
        $g.FillRectangle($bgBrush, 0, 0, $Size, $Size)
    } else {
        $p = New-Object System.Drawing.Drawing2D.GraphicsPath
        Add-RoundRect -Path $p -X 0 -Y 0 -W $Size -H $Size -R ($Size * 0.18)
        $g.FillPath($bgBrush, $p)
        $p.Dispose()
    }

    # viewBox 0..48 x, content y 6..114 (height 108). Scale to target.
    [double]$H = $Size * $LadderFrac
    [double]$s = $H / 108.0
    [double]$W = 37.0 * $s
    [double]$left = ($Size - $W) / 2.0
    [double]$top = ($Size - $H) / 2.0
    function VX([double]$vx) { return $left + ($vx - 5.5) * $s }
    function VY([double]$vy) { return $top + ($vy - 6.0) * $s }

    $accBrush = New-Object System.Drawing.SolidBrush($accent)
    $dimBrush = New-Object System.Drawing.SolidBrush($dim)
    $liteBrush = New-Object System.Drawing.SolidBrush($lite)
    $boltBrush = New-Object System.Drawing.SolidBrush($bolt)

    function Fill-VBRoundRect {
        param([System.Drawing.Brush]$Brush, [double]$X, [double]$Y, [double]$Wd, [double]$Ht, [double]$R)
        $bp = New-Object System.Drawing.Drawing2D.GraphicsPath
        Add-RoundRect -Path $bp -X (VX $X) -Y (VY $Y) -W ($Wd * $s) -H ($Ht * $s) -R ($R * $s)
        $g.FillPath($Brush, $bp)
        $bp.Dispose()
    }
    function Fill-VBDot {
        param([System.Drawing.Brush]$Brush, [double]$Cx, [double]$Cy, [double]$Rad)
        $rp = $Rad * $s
        $g.FillEllipse($Brush, (VX $Cx) - $rp, (VY $Cy) - $rp, 2 * $rp, 2 * $rp)
    }

    # rails
    Fill-VBRoundRect $accBrush 5.5 6 5 108 2.5
    Fill-VBRoundRect $accBrush 37.5 6 5 108 2.5

    # rungs: [x, y, w, h, rx, dim?]
    $rungs = @(
        @(6, 16,    36, 6, 3,   $false),
        @(6, 33.5,  28, 5, 2.5, $true),
        @(6, 50.5,  22, 5, 2.5, $true),
        @(6, 67.5,  17, 5, 2.5, $true),
        @(6, 84.5,  13, 5, 2.5, $true),
        @(6, 101.5, 10, 5, 2.5, $true)
    )
    foreach ($r in $rungs) {
        $brush = if ($r[5]) { $dimBrush } else { $accBrush }
        Fill-VBRoundRect $brush $r[0] $r[1] $r[2] $r[3] $r[4]
    }
    # rung top highlights
    $hi = @(
        @(7, 16,    33, 1.8),
        @(7, 33.5,  25, 1.5),
        @(7, 50.5,  19, 1.5),
        @(7, 67.5,  14, 1.5),
        @(7, 84.5,  10, 1.5),
        @(7, 101.5, 7,  1.5)
    )
    foreach ($h2 in $hi) { Fill-VBRoundRect $liteBrush $h2[0] $h2[1] $h2[2] $h2[3] ($h2[3] / 2.0) }

    # bolt heads where rungs meet the rails
    Fill-VBDot $boltBrush 8 19 1.9
    Fill-VBDot $boltBrush 40 19 1.9
    foreach ($cy in @(36, 53, 70, 87, 104)) { Fill-VBDot $boltBrush 8 $cy 1.7 }

    $g.Dispose()
    $bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "wrote $OutPath"
}

$dir = "D:\Claude Code\portfolio\games\3-2-1"
New-Icon -Size 192 -LadderFrac 0.64 -OutPath "$dir\icon-192.png"
New-Icon -Size 512 -LadderFrac 0.64 -OutPath "$dir\icon-512.png"
New-Icon -Size 512 -LadderFrac 0.50 -OutPath "$dir\icon-maskable-512.png" -Maskable

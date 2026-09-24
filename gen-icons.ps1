Add-Type -AssemblyName System.Drawing

# Daily Climb app icon: navy ground + the summit mark — the sun rising behind a
# back peak, the main peak with the dotted trail you climb, and a flag on top.
# Drawn from the same 64x56 viewBox as the in-app brandmark (index.html).

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
    param([int]$Size, [double]$MarkFrac, [string]$OutPath, [switch]$Maskable)

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    $bg = [System.Drawing.Color]::FromArgb(18, 20, 31)        # #12141f (--bg)
    $accent = [System.Drawing.Color]::FromArgb(232, 135, 30)  # #e8871e (--accent)
    $sun = Blend $bg $accent 0.65                             # fill-opacity .65
    $back = Blend $bg $accent 0.38                            # back peak, fill-opacity .38

    $bgBrush = New-Object System.Drawing.SolidBrush($bg)
    if ($Maskable) {
        $g.FillRectangle($bgBrush, 0, 0, $Size, $Size)
    } else {
        $p = New-Object System.Drawing.Drawing2D.GraphicsPath
        Add-RoundRect -Path $p -X 0 -Y 0 -W $Size -H $Size -R ($Size * 0.18)
        $g.FillPath($bgBrush, $p)
        $p.Dispose()
    }

    # viewBox 64 x 56, centred; the mark spans MarkFrac of the icon's width.
    [double]$s = $Size * $MarkFrac / 64.0
    [double]$left = ($Size - 64.0 * $s) / 2.0
    [double]$top = ($Size - 56.0 * $s) / 2.0
    function P([double]$vx, [double]$vy) { return New-Object System.Drawing.PointF([single]($left + $vx * $s), [single]($top + $vy * $s)) }
    function Poly([System.Drawing.Color]$c, [double[]]$xy) {
        $pts = @(); for ($i = 0; $i -lt $xy.Length; $i += 2) { $pts += (P $xy[$i] $xy[$i + 1]) }
        $b = New-Object System.Drawing.SolidBrush($c); $g.FillPolygon($b, [System.Drawing.PointF[]]$pts); $b.Dispose()
    }
    function Dot([System.Drawing.Color]$c, [double]$cx, [double]$cy, [double]$r) {
        $b = New-Object System.Drawing.SolidBrush($c)
        $g.FillEllipse($b, [single]($left + ($cx - $r) * $s), [single]($top + ($cy - $r) * $s), [single](2 * $r * $s), [single](2 * $r * $s))
        $b.Dispose()
    }

    # sun, then the back peak over it, then the main peak
    Dot $sun 44 25 11
    Poly $back @(30, 54, 45, 28, 62, 54)
    Poly $accent @(2, 54, 26, 14, 50, 54)

    # dotted trail up the main peak: a dot every 4.7 units along the polyline
    $trail = @(@(11, 51), @(22, 44), @(15, 36), @(25, 27), @(21, 21))
    [double]$carry = 0
    for ($i = 0; $i -lt $trail.Length - 1; $i++) {
        $ax = $trail[$i][0]; $ay = $trail[$i][1]; $bx = $trail[$i + 1][0]; $by = $trail[$i + 1][1]
        $len = [Math]::Sqrt(($bx - $ax) * ($bx - $ax) + ($by - $ay) * ($by - $ay))
        for ([double]$d = $carry; $d -le $len; $d += 4.7) {
            $t = $d / $len
            Dot $bg ($ax + ($bx - $ax) * $t) ($ay + ($by - $ay) * $t) 1.2
        }
        $carry = 4.7 - (($len - $carry) % 4.7)
        if ($carry -ge 4.7) { $carry = 0 }
    }

    # flag pole + swallowtail flag
    $pen = New-Object System.Drawing.Pen($accent, [single](2 * $s))
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($pen, (P 26 14), (P 26 3))
    $pen.Dispose()
    Poly $accent @(26, 3.5, 36, 3.5, 33.4, 6.7, 36, 9.9, 26, 9.9)

    $g.Dispose()
    $bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "wrote $OutPath"
}

$dir = "D:\Claude Code\portfolio\games\3-2-1"
New-Icon -Size 192 -MarkFrac 0.70 -OutPath "$dir\icon-192.png"
New-Icon -Size 512 -MarkFrac 0.70 -OutPath "$dir\icon-512.png"
New-Icon -Size 512 -MarkFrac 0.56 -OutPath "$dir\icon-maskable-512.png" -Maskable

Add-Type -AssemblyName System.Drawing

# Daily Climb app icon: the home screen's sticker logo (two peaks, snowcaps, a
# yellow flag, the dotted trail and the climber) on the splash apricot.
# Drawn from the same 120x92 viewBox as the .hs-logo / #summit-mark SVG in index.html.

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
    param([int]$Size, [double]$MarkFrac, [string]$OutPath, [switch]$Maskable)

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    $splash = [System.Drawing.Color]::FromArgb(244, 211, 166)  # #f4d3a6 (--hs-bg, light)
    $ink    = [System.Drawing.Color]::FromArgb(18, 18, 18)     # #121212
    $far    = [System.Drawing.Color]::FromArgb(246, 180, 106)  # #f6b46a
    $near   = [System.Drawing.Color]::FromArgb(232, 135, 30)   # #e8871e
    $gold   = [System.Drawing.Color]::FromArgb(246, 201, 14)   # #f6c90e
    $white  = [System.Drawing.Color]::White

    $bgBrush = New-Object System.Drawing.SolidBrush($splash)
    if ($Maskable) {
        $g.FillRectangle($bgBrush, 0, 0, $Size, $Size)
    } else {
        $p = New-Object System.Drawing.Drawing2D.GraphicsPath
        Add-RoundRect -Path $p -X 0 -Y 0 -W $Size -H $Size -R ($Size * 0.18)
        $g.FillPath($bgBrush, $p)
        $p.Dispose()
    }

    # viewBox 120 x 92, centred (nudged up a touch: the flag is light, the base is heavy).
    [double]$s = $Size * $MarkFrac / 120.0
    [double]$left = ($Size - 120.0 * $s) / 2.0
    [double]$top = ($Size - 92.0 * $s) / 2.0 - $Size * 0.01
    function P([double]$vx, [double]$vy) { return New-Object System.Drawing.PointF([single]($left + $vx * $s), [single]($top + $vy * $s)) }
    function Pts([double[]]$xy) { $pts = @(); for ($i = 0; $i -lt $xy.Length; $i += 2) { $pts += (P $xy[$i] $xy[$i + 1]) }; return [System.Drawing.PointF[]]$pts }
    function InkPen([double]$w) {
        $pen = New-Object System.Drawing.Pen($ink, [single]($w * $s))
        $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
        $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
        $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
        return $pen
    }
    # filled shape with the sticker's 4-unit ink outline
    function Shape([System.Drawing.Color]$c, [double[]]$xy) {
        $pts = Pts $xy
        $b = New-Object System.Drawing.SolidBrush($c); $g.FillPolygon($b, $pts); $b.Dispose()
        $pen = InkPen 4; $g.DrawPolygon($pen, $pts); $pen.Dispose()
    }

    Shape $far  @(6, 84, 34, 42, 52, 66, 74, 26, 98, 60, 114, 84)
    Shape $near @(52, 66, 74, 26, 98, 60, 114, 84, 40, 84)
    Shape $white @(66, 40, 74, 26, 83, 39, 78, 36, 74, 42, 70, 37)
    Shape $white @(28, 51, 34, 42, 40, 50, 36, 48, 33, 53)
    $pen = InkPen 4; $g.DrawLine($pen, (P 74 26), (P 74 6)); $pen.Dispose()
    Shape $gold @(74, 6, 92, 11, 74, 17)

    # dotted trail: the curve M18 80 C30 74 44 70 56 60, a dot every ~7 units
    $dot = New-Object System.Drawing.SolidBrush($ink)
    $prev = $null; [double]$acc = 7
    for ($i = 0; $i -le 400; $i++) {
        $t = $i / 400.0; $u = 1 - $t
        $x = $u * $u * $u * 18 + 3 * $u * $u * $t * 30 + 3 * $u * $t * $t * 44 + $t * $t * $t * 56
        $y = $u * $u * $u * 80 + 3 * $u * $u * $t * 74 + 3 * $u * $t * $t * 70 + $t * $t * $t * 60
        if ($prev) { $acc += [Math]::Sqrt(($x - $prev[0]) * ($x - $prev[0]) + ($y - $prev[1]) * ($y - $prev[1])) }
        $prev = @($x, $y)
        if ($acc -ge 7 -and $t -lt 0.9) {
            $acc = 0; $r = 1.3
            $g.FillEllipse($dot, [single]($left + ($x - $r) * $s), [single]($top + ($y - $r) * $s), [single](2 * $r * $s), [single](2 * $r * $s))
        }
    }
    $dot.Dispose()

    # the climber
    $r = 6
    $wb = New-Object System.Drawing.SolidBrush($white)
    $rect = New-Object System.Drawing.RectangleF([single]($left + (56 - $r) * $s), [single]($top + (60 - $r) * $s), [single](2 * $r * $s), [single](2 * $r * $s))
    $g.FillEllipse($wb, $rect); $wb.Dispose()
    $pen = InkPen 3.5; $g.DrawEllipse($pen, $rect); $pen.Dispose()

    $g.Dispose()
    $bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    Write-Host "wrote $OutPath"
}

$dir = "D:\Claude Code\daily-climb"
New-Icon -Size 192 -MarkFrac 0.78 -OutPath "$dir\icon-192.png"
New-Icon -Size 512 -MarkFrac 0.78 -OutPath "$dir\icon-512.png"
New-Icon -Size 512 -MarkFrac 0.60 -OutPath "$dir\icon-maskable-512.png" -Maskable

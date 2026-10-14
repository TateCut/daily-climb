Add-Type -AssemblyName System.Drawing

# Daily Climb app icon: the home screen's sticker logo (three peaks for the 6-7-8 Climbs - small left, medium
# right, the tall flagged one in the middle - with snowcaps, the dotted trail and the climber) on the splash apricot.
# Drawn from the same "0 -10 132 100" viewBox as the .hs-logo / #summit-mark SVG in index.html.

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

    # viewBox 0 -10 132 100, centred (nudged up a touch: the flag is light, the base is heavy).
    [double]$s = $Size * $MarkFrac / 132.0
    [double]$left = ($Size - 132.0 * $s) / 2.0
    [double]$top = ($Size - 100.0 * $s) / 2.0 - $Size * 0.01 + 10.0 * $s
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

    Shape $far  @(4, 84, 26, 50, 50, 84)                                          # small peak (Climb 1)
    Shape $white @(21.2, 58.4, 26, 50, 31.4, 57.8, 28.4, 56, 26, 59.6, 23.6, 56.6)
    Shape $far  @(74, 84, 102, 36, 128, 84)                                       # medium peak (Climb 2)
    Shape $white @(96, 46.5, 102, 36, 108.75, 45.75, 105, 43.5, 102, 48, 99, 44.25)
    Shape $near @(28, 84, 64, 14, 102, 84)                                        # tall peak (Climb 3), in front
    Shape $white @(56, 28, 64, 14, 73, 27, 68, 24, 64, 30, 60, 25)
    $pen = InkPen 4; $g.DrawLine($pen, (P 64 14), (P 64 -6)); $pen.Dispose()
    Shape $gold @(64, -6, 82, -1, 64, 5)

    # dotted trail: the curve M10 82 C18 78 28 72 38 64, a dot every ~7 units
    $dot = New-Object System.Drawing.SolidBrush($ink)
    $prev = $null; [double]$acc = 7
    for ($i = 0; $i -le 400; $i++) {
        $t = $i / 400.0; $u = 1 - $t
        $x = $u * $u * $u * 10 + 3 * $u * $u * $t * 18 + 3 * $u * $t * $t * 28 + $t * $t * $t * 38
        $y = $u * $u * $u * 82 + 3 * $u * $u * $t * 78 + 3 * $u * $t * $t * 72 + $t * $t * $t * 64
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
    $rect = New-Object System.Drawing.RectangleF([single]($left + (39 - $r) * $s), [single]($top + (63 - $r) * $s), [single](2 * $r * $s), [single](2 * $r * $s))
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

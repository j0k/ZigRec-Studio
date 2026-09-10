# -*- coding: utf-8 -*-
r"""Снимок окна для README: аккуратный, а не «как сфотографировалось».

Прямой снимок окна выглядит плохо по трём причинам, и все три лечатся здесь.

1. `GetWindowRect` отдаёт прямоугольник вместе с невидимой рамкой изменения
   размера. Рисовать в ней нечего, и в снимке она выходит чёрной каймой.
   Настоящие границы знает система — `DwmGetWindowAttribute`; по ним и режем.
   Искать край по цвету бесполезно: заголовок окна светлый и тянется во всю
   ширину снимка, так что «первый нечёрный столбец» находится сразу, а полоса
   слева остаётся.
2. У окна Windows скруглённые углы, а снимок отдаёт прямые. Скругляем сами.
3. Снимок без полей и тени выглядит вырезанным ножницами. Кладём окно
   на прозрачный холст с мягкой тенью и полями.

Фон прозрачный нарочно: на GitHub страница бывает и светлая, и тёмная,
и белая подложка в тёмной теме смотрелась бы заплаткой.

Запуск (окно должно быть открыто):
    python tools\make_screenshot.py
"""
import io
import os
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
RAW = os.path.join(REPO, ".check", "window-raw.png")
INSET = os.path.join(REPO, ".check", "window-inset.txt")
OUT = os.path.join(REPO, "assets", "screenshot.png")

# Снимок окна делает PowerShell: у него под рукой PrintWindow, который берёт
# содержимое окна, даже если сверху что-то лежит.
GRAB = r'''
Add-Type -AssemblyName System.Drawing
$src = @"
using System;using System.Text;using System.Runtime.InteropServices;using System.Collections.Generic;
public class Grab {
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out RECT r, int size);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint flags);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left,Top,Right,Bottom; }
  public static List<IntPtr> F = new List<IntPtr>();
  public static void Scan(string cls) { F.Clear();
    EnumWindows(delegate(IntPtr h, IntPtr p) { var sb=new StringBuilder(256); GetClassNameW(h,sb,256);
      if (sb.ToString()==cls && IsWindowVisible(h)) F.Add(h); return true; }, IntPtr.Zero); }
}
"@
Add-Type -TypeDefinition $src
[Grab]::SetProcessDPIAware() | Out-Null
[Grab]::Scan("ZigRecMain")
if ([Grab]::F.Count -eq 0) { Write-Error "окно не найдено"; exit 1 }
$h = [Grab]::F[0]
$r = New-Object Grab+RECT
[Grab]::GetWindowRect($h, [ref]$r) | Out-Null
$w = $r.Right - $r.Left; $ht = $r.Bottom - $r.Top
$bmp = New-Object System.Drawing.Bitmap($w, $ht)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$dc = $g.GetHdc()
[Grab]::PrintWindow($h, $dc, 2) | Out-Null
$g.ReleaseHdc($dc)
$bmp.Save("%OUT%")
# Настоящие границы окна: без невидимой рамки изменения размера.
$f = New-Object Grab+RECT
$ok = [Grab]::DwmGetWindowAttribute($h, 9, [ref]$f, 16)
if ($ok -eq 0) {
  "$($f.Left - $r.Left) $($f.Top - $r.Top) $($r.Right - $f.Right) $($r.Bottom - $f.Bottom)" |
    Set-Content -Path "%INSET%" -Encoding ascii
}
'''


def grab(path, inset_path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.isfile(inset_path):
        os.remove(inset_path)
    script = GRAB.replace("%OUT%", path.replace("\\", "\\\\"))
    script = script.replace("%INSET%", inset_path.replace("\\", "\\\\"))
    out = subprocess.run(
        ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    if not os.path.isfile(path):
        sys.stderr.write(out.stdout + out.stderr)
        raise SystemExit("не удалось снять окно: оно открыто?")
    if not os.path.isfile(inset_path):
        return (0, 0, 0, 0)
    with io.open(inset_path, encoding="ascii") as f:
        return tuple(int(v) for v in f.read().split())


def crop_black_border(img):
    """Убрать чёрную кайму невидимой рамки окна.

    Ищем первую строку и первый столбец, где есть хоть что-то не чёрное.
    Порог не нулевой: край рамки бывает не идеально чёрным.
    """
    grey = img.convert("L")
    w, h = grey.size
    px = grey.load()
    threshold = 24

    def row_has_content(y):
        return any(px[x, y] > threshold for x in range(0, w, 3))

    def col_has_content(x):
        return any(px[x, y] > threshold for y in range(0, h, 3))

    top = next((y for y in range(h) if row_has_content(y)), 0)
    bottom = next((y for y in range(h - 1, -1, -1) if row_has_content(y)), h - 1)
    left = next((x for x in range(w) if col_has_content(x)), 0)
    right = next((x for x in range(w - 1, -1, -1) if col_has_content(x)), w - 1)
    return img.crop((left, top, right + 1, bottom + 1))


def round_corners(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.size[0] - 1, img.size[1] - 1],
                                           radius=radius, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def with_shadow(img, pad=36, blur=14, offset=8, opacity=70):
    """Мягкая тень под окном на прозрачном холсте."""
    w, h = img.size
    canvas = Image.new("RGBA", (w + pad * 2, h + pad * 2), (0, 0, 0, 0))

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [pad, pad + offset, pad + w, pad + h + offset],
        radius=10, fill=(0, 0, 0, opacity),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))

    canvas.alpha_composite(shadow)
    canvas.alpha_composite(img, (pad, pad))
    return canvas


def main():
    inset = grab(RAW, INSET)
    raw = Image.open(RAW).convert("RGB")
    w, h = raw.size
    left, top, right, bottom = inset
    body = raw.crop((left, top, w - right, h - bottom))
    # Подстраховка: если система границ не дала, режем по цвету.
    if inset == (0, 0, 0, 0):
        body = crop_black_border(raw)
    rounded = round_corners(body, radius=10)
    final = with_shadow(rounded)
    final.save(OUT)
    print("снимок:", OUT, final.size, "было", raw.size, "срезано", inset)


if __name__ == "__main__":
    main()

"""App icon (radar + disco ball + B) from the SVG masters in this folder to every Android / iOS / Play size.

Renders each SVG at 1024 px with headless Chrome (transparent background) and downsizes with Pillow.
Run from anywhere: python branding/build_icons.py  (needs Google Chrome and Pillow).

- icon_foreground.svg / icon_monochrome.svg: adaptive icon layers, 108dp canvas with the content inside the
  66dp safe circle, so no launcher mask (circle, squircle, teardrop) cuts it. The background layer is
  res/drawable/ic_launcher_background.xml (same gradient as icon_background.svg).
- icon_rounded.svg / icon_round.svg: legacy launchers (before Android 8).
- icon_square.svg: iOS (the system rounds it; no alpha allowed) and the Play Store listing (512 px).
"""
import json
import subprocess
import tempfile
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
APP = HERE.parent
RES = APP / 'android' / 'app' / 'src' / 'main' / 'res'
IOS = APP / 'ios' / 'Runner' / 'Assets.xcassets' / 'AppIcon.appiconset'
CHROME = r'C:\Program Files\Google\Chrome\Application\chrome.exe'

# density -> scale over mdpi (legacy icon 48dp, adaptive layers 108dp)
DENSITIES = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}


def render(name: str, out_dir: Path) -> Image.Image:
    out = out_dir / f'{name}.png'
    subprocess.run([CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars', '--default-background-color=00000000',
                    '--window-size=1024,1024', f'--screenshot={out}', (HERE / f'{name}.svg').as_uri()],
                   check=True, capture_output=True)
    return Image.open(out).convert('RGBA')


def save(im: Image.Image, size: int, path: Path, alpha: bool = True) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    small = im.resize((size, size), Image.LANCZOS)
    (small if alpha else small.convert('RGB')).save(path, optimize=True)


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        icons = {n: render(n, tmp) for n in ['icon_foreground', 'icon_monochrome', 'icon_rounded', 'icon_round', 'icon_square']}

    for density, scale in DENSITIES.items():
        folder = RES / f'mipmap-{density}'
        save(icons['icon_rounded'], round(48 * scale), folder / 'ic_launcher.png')
        save(icons['icon_round'], round(48 * scale), folder / 'ic_launcher_round.png')
        save(icons['icon_foreground'], round(108 * scale), folder / 'ic_launcher_foreground.png')
        save(icons['icon_monochrome'], round(108 * scale), folder / 'ic_launcher_monochrome.png')

    contents = json.loads((IOS / 'Contents.json').read_text(encoding='utf-8'))
    for image in contents['images']:
        if 'filename' in image:
            points = float(image['size'].split('x')[0])
            save(icons['icon_square'], round(points * int(image['scale'][0])), IOS / image['filename'], alpha=False)

    save(icons['icon_square'], 512, HERE / 'play_store_512.png', alpha=False)
    print('icons written')


if __name__ == '__main__':
    main()

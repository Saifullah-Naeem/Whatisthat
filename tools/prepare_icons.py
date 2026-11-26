"""Prepare PNG and multi-resolution Windows ICO assets from the generated app icon."""

from pathlib import Path
from PIL import Image


def main() -> None:
    repo_root = Path(__file__).resolve().parent.parent
    src = Path(
        "/home/falcon/.gemini/antigravity-cli/brain/5d310ef7-3a81-4636-acdd-ff45a002c1fb/whatisthat_app_icon_1795712369398.jpg"
    )
    icon_dir = repo_root / "assets" / "icon"
    icon_dir.mkdir(parents=True, exist_ok=True)

    img = Image.open(src).convert("RGBA")
    png_path = icon_dir / "app_icon.png"
    img.resize((1024, 1024), Image.Resampling.LANCZOS).save(png_path, format="PNG")

    ico_path = icon_dir / "app_icon.ico"
    img.save(
        ico_path,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    print(f"Generated {png_path} and {ico_path}")


if __name__ == "__main__":
    main()

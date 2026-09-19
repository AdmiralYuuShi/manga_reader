"""Optional real-model smoke path: python tests/model_smoke.py path/to/page.png"""

import sys
from pathlib import Path

from PIL import Image, ImageOps

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.config import get_settings
from app.services.detection.comic_text_detector import ComicTextDetector


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python tests/model_smoke.py path/to/manga-page.png")
    settings = get_settings()
    detector = ComicTextDetector(settings.detector_source, settings.detector_model)
    with Image.open(sys.argv[1]) as image:
        regions = detector.detect(ImageOps.exif_transpose(image).convert("RGB"))
    print(f"Detected {len(regions)} regions")

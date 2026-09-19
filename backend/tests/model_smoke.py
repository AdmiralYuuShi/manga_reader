"""Optional real-model smoke path: python tests/model_smoke.py path/to/page.png"""

import sys
import json
from pathlib import Path

from PIL import Image, ImageOps

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.config import get_settings
from app.services.detection.comic_text_detector import ComicTextDetector
from app.services.image_crops import crop_region
from app.services.ocr.manga_ocr import MangaOcrEngine


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python tests/model_smoke.py path/to/manga-page.png")
    settings = get_settings()
    detector = ComicTextDetector(settings.detector_source, settings.detector_model)
    with Image.open(sys.argv[1]) as image:
        page = ImageOps.exif_transpose(image).convert("RGB")
    regions = detector.detect(page)
    print(f"Detected {len(regions)} regions")
    if not regions:
        raise SystemExit("No regions to verify OCR")
    crop = crop_region(page, regions[0])
    if crop is None:
        raise SystemExit("First region could not be cropped")
    ocr = MangaOcrEngine(settings.ocr_model)
    text = ocr.recognize(crop)
    print(json.dumps({"first_crop_size": crop.size, "source_text": text}, ensure_ascii=True))

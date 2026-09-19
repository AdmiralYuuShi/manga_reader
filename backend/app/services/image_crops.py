from PIL import Image

from app.services.detection.base import DetectedRegion


def crop_region(image: Image.Image, region: DetectedRegion) -> Image.Image | None:
    """Clip a detector box to the decoded original page before OCR."""
    left = max(0, min(image.width, region.x))
    top = max(0, min(image.height, region.y))
    right = max(0, min(image.width, region.x + region.width))
    bottom = max(0, min(image.height, region.y + region.height))
    if right <= left or bottom <= top:
        return None
    return image.crop((left, top, right, bottom))

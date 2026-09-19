import asyncio

from PIL import Image

from app.services.detection.base import DetectedRegion
from app.services.image_crops import crop_region
from app.services.manga_processor import MangaProcessor


class FakeDetector:
    def __init__(self, regions):
        self.regions = regions

    def detect(self, image):
        return self.regions


class FakeOcr:
    def __init__(self):
        self.crops = []

    def recognize(self, image):
        self.crops.append((image.size, image.getpixel((0, 0))))
        if image.getpixel((0, 0)) == (255, 0, 0):
            return "今日は"
        return "学校"


def process(image, regions, ocr):
    async def run():
        processor = MangaProcessor(FakeDetector(regions), ocr, asyncio.Lock(), asyncio.Lock())
        return await processor.process(image)

    return asyncio.run(run())


def test_crops_original_image_and_preserves_region_ids():
    image = Image.new("RGB", (20, 10), "red")
    image.paste("blue", (10, 0, 20, 10))
    ocr = FakeOcr()
    result = process(image, [DetectedRegion(0, 0, 10, 10), DetectedRegion(10, 0, 10, 10)], ocr)
    assert ocr.crops == [((10, 10), (255, 0, 0)), ((10, 10), (0, 0, 255))]
    assert [(item.id, item.source_text) for item in result.regions] == [
        ("region_001", "今日は"), ("region_002", "学校")
    ]
    assert result.detection_ms >= 0 and result.ocr_ms >= 0


def test_empty_text_and_per_region_error():
    class IntermittentOcr:
        def __init__(self):
            self.calls = 0

        def recognize(self, image):
            self.calls += 1
            if self.calls == 2:
                raise RuntimeError("private error")
            return ""

    result = process(Image.new("RGB", (20, 10)),
                     [DetectedRegion(0, 0, 5, 5), DetectedRegion(5, 0, 5, 5),
                      DetectedRegion(10, 0, 5, 5)], IntermittentOcr())
    assert [item.source_text for item in result.regions] == ["", None, ""]
    assert [item.error_code for item in result.regions] == [None, "OCR_FAILED", None]


def test_invalid_crop_is_local_failure():
    ocr = FakeOcr()
    result = process(Image.new("RGB", (20, 10)), [DetectedRegion(30, 0, 5, 5)], ocr)
    assert result.regions[0].error_code == "OCR_INVALID_CROP"
    assert ocr.crops == []
    assert crop_region(Image.new("RGB", (20, 10)), DetectedRegion(-2, -1, 5, 5)).size == (3, 4)

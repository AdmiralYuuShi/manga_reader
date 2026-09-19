import asyncio

from PIL import Image

from app.services.detection.base import DetectedRegion
from app.services.image_crops import crop_region
from app.services.manga_processor import MangaProcessor
from app.services.translation.base import TranslationItem


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


class FakeTranslator:
    def __init__(self, fail=False):
        self.batches = []
        self.fail = fail

    def translate_batch(self, texts, source_language, target_language):
        self.batches.append((texts, source_language, target_language))
        if self.fail:
            raise RuntimeError("provider unavailable")
        return [TranslationItem(translated_text=f"Indonesian {index}")
                for index, _ in enumerate(texts)]


def process(image, regions, ocr, translator=None, translate=True, target_language="id"):
    async def run():
        processor = MangaProcessor(FakeDetector(regions), ocr, asyncio.Lock(), asyncio.Lock(),
                                   translator or FakeTranslator())
        return await processor.process(image, translate=translate, target_language=target_language)

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
    assert result.regions[0].translated_text == "Indonesian 0"


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
    assert all(item.translated_text is None for item in result.regions)


def test_invalid_crop_is_local_failure():
    ocr = FakeOcr()
    result = process(Image.new("RGB", (20, 10)), [DetectedRegion(30, 0, 5, 5)], ocr)
    assert result.regions[0].error_code == "OCR_INVALID_CROP"
    assert ocr.crops == []
    assert crop_region(Image.new("RGB", (20, 10)), DetectedRegion(-2, -1, 5, 5)).size == (3, 4)


def test_batch_skips_empty_ocr_and_preserves_order():
    class MixedOcr:
        def __init__(self):
            self.calls = 0

        def recognize(self, image):
            self.calls += 1
            return ["first", "  ", "third"][self.calls - 1]

    translator = FakeTranslator()
    result = process(Image.new("RGB", (20, 10)),
                     [DetectedRegion(0, 0, 5, 5), DetectedRegion(5, 0, 5, 5),
                      DetectedRegion(10, 0, 5, 5)], MixedOcr(), translator,
                     target_language="en")
    assert translator.batches == [(["first", "third"], "ja", "en")]
    assert [r.translated_text for r in result.regions] == ["Indonesian 0", None, "Indonesian 1"]
    assert result.translation_ms >= 0


def test_translation_failure_and_disabled_path_preserve_ocr():
    region = [DetectedRegion(0, 0, 5, 5)]
    failing = FakeTranslator(fail=True)
    failed = process(Image.new("RGB", (20, 10), "red"), region, FakeOcr(), failing)
    assert failed.regions[0].source_text is not None
    assert failed.regions[0].translation_error_code == "TRANSLATION_FAILED"
    disabled = process(Image.new("RGB", (20, 10), "red"), region, FakeOcr(),
                       failing, translate=False)
    assert disabled.regions[0].source_text == failed.regions[0].source_text
    assert disabled.regions[0].translated_text is None
    assert disabled.regions[0].translation_error_code is None
    assert disabled.translation_ms == 0
    assert len(failing.batches) == 1


def test_partial_failure_keeps_region_mapping():
    class MixedTranslator:
        def translate_batch(self, texts, source_language, target_language):
            assert texts == ["one", "two", "three"]
            return [TranslationItem(translated_text="satu"),
                    TranslationItem(error_code="TRANSLATION_FAILED"),
                    TranslationItem(translated_text="tiga")]

    class SequenceOcr:
        def __init__(self):
            self.calls = 0

        def recognize(self, image):
            value = ["one", "two", "three"][self.calls]
            self.calls += 1
            return value

    result = process(Image.new("RGB", (20, 10)),
                     [DetectedRegion(0, 0, 5, 5), DetectedRegion(5, 0, 5, 5),
                      DetectedRegion(10, 0, 5, 5)], SequenceOcr(), MixedTranslator())
    assert [(r.id, r.translated_text, r.translation_error_code) for r in result.regions] == [
        ("region_001", "satu", None),
        ("region_002", None, "TRANSLATION_FAILED"),
        ("region_003", "tiga", None),
    ]

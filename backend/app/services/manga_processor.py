import asyncio
import logging
from dataclasses import dataclass, replace
from time import perf_counter

from fastapi.concurrency import run_in_threadpool
from PIL import Image

from app.services.detection.base import DetectedRegion, TextDetector
from app.services.image_crops import crop_region
from app.services.ocr.base import OcrEngine
from app.services.translation.base import Translator

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class ProcessedRegion:
    id: str
    bbox: DetectedRegion
    source_text: str | None
    error_code: str | None = None
    translated_text: str | None = None
    translation_error_code: str | None = None


@dataclass(frozen=True)
class ProcessingResult:
    regions: list[ProcessedRegion]
    detection_ms: int
    ocr_ms: int
    translation_ms: int


class DetectionFailed(Exception):
    pass


class MangaProcessor:
    def __init__(
        self,
        detector: TextDetector,
        ocr: OcrEngine,
        detector_lock: asyncio.Lock,
        ocr_lock: asyncio.Lock,
        translator: Translator,
    ) -> None:
        self.detector = detector
        self.ocr = ocr
        self.detector_lock = detector_lock
        self.ocr_lock = ocr_lock
        self.translator = translator

    async def process(
        self, image: Image.Image, *, translate: bool = True, target_language: str = "id"
    ) -> ProcessingResult:
        detection_start = perf_counter()
        try:
            async with self.detector_lock:
                detected = await run_in_threadpool(self.detector.detect, image)
        except Exception as exc:
            raise DetectionFailed from exc
        detection_ms = round((perf_counter() - detection_start) * 1000)

        ocr_start = perf_counter()
        regions = []
        for index, bbox in enumerate(detected, start=1):
            region_id = f"region_{index:03d}"
            crop = crop_region(image, bbox)
            if crop is None:
                regions.append(ProcessedRegion(region_id, bbox, None, "OCR_INVALID_CROP"))
                continue
            try:
                async with self.ocr_lock:
                    text = await run_in_threadpool(self.ocr.recognize, crop)
                regions.append(ProcessedRegion(region_id, bbox, text))
            except Exception:
                logger.exception("OCR failed for %s", region_id)
                regions.append(ProcessedRegion(region_id, bbox, None, "OCR_FAILED"))
        ocr_ms = round((perf_counter() - ocr_start) * 1000)
        logger.info("Detected %d regions; OCR succeeded for %d/%d", len(regions),
                    sum(region.error_code is None for region in regions), len(regions))
        translation_start = perf_counter()
        candidates = [index for index, region in enumerate(regions)
                      if region.error_code is None and region.source_text and region.source_text.strip()]
        if translate and candidates:
            try:
                translated = await run_in_threadpool(
                    self.translator.translate_batch,
                    [regions[index].source_text for index in candidates], "ja", target_language,
                )
                if len(translated) != len(candidates):
                    raise ValueError("Translation batch length differs from OCR input")
                for index, item in zip(candidates, translated):
                    regions[index] = replace(regions[index],
                                             translated_text=item.translated_text,
                                             translation_error_code=item.error_code)
            except Exception:
                logger.exception("Translation failed for %d regions", len(candidates))
                for index in candidates:
                    regions[index] = replace(regions[index],
                                             translation_error_code="TRANSLATION_FAILED")
        translation_ms = round((perf_counter() - translation_start) * 1000) if translate and candidates else 0
        return ProcessingResult(regions, detection_ms, ocr_ms, translation_ms)

import asyncio
import logging
from dataclasses import dataclass, replace
from time import perf_counter

from fastapi.concurrency import run_in_threadpool
from PIL import Image

from app.services.detection.base import DetectedRegion, TextDetector
from app.services.image_crops import crop_region
from app.services.ocr.base import OcrEngine
from app.services.performance import PerformanceMetrics, current_metrics
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
        self, image: Image.Image, *, translate: bool = True, target_language: str = "id",
        metrics: PerformanceMetrics | None = None,
    ) -> ProcessingResult:
        metrics = metrics or PerformanceMetrics()
        metrics.provider = type(self.translator).__name__ if translate else "disabled"
        for name in ("regions", "ocr_attempted", "ocr_succeeded", "ocr_failed",
                     "ocr_invalid_crop", "translation_candidates", "translation_skipped",
                     "translation_requests", "translation_failed", "duplicate_source_texts"):
            metrics.count(name, 0)
        detection_start = perf_counter()
        try:
            with metrics.stage("detection", getattr(self.detector, "device", "cpu")):
                async with self.detector_lock:
                    detected = await run_in_threadpool(self.detector.detect, image)
        except Exception as exc:
            raise DetectionFailed from exc
        detection_ms = round((perf_counter() - detection_start) * 1000)
        metrics.count("regions", len(detected))

        ocr_start = perf_counter()
        regions = []
        for index, bbox in enumerate(detected, start=1):
            region_id = f"region_{index:03d}"
            with metrics.stage("crop_prepare"):
                crop = crop_region(image, bbox)
            if crop is None:
                metrics.count("ocr_invalid_crop")
                regions.append(ProcessedRegion(region_id, bbox, None, "OCR_INVALID_CROP"))
                continue
            metrics.count("ocr_attempted")
            try:
                with metrics.stage("ocr_inference", getattr(self.ocr, "device", "cpu")):
                    async with self.ocr_lock:
                        text = await run_in_threadpool(self.ocr.recognize, crop)
                regions.append(ProcessedRegion(region_id, bbox, text))
                metrics.count("ocr_succeeded")
            except Exception:
                metrics.count("ocr_failed")
                logger.exception("OCR failed for %s", region_id)
                regions.append(ProcessedRegion(region_id, bbox, None, "OCR_FAILED"))
        ocr_ms = round((perf_counter() - ocr_start) * 1000)
        logger.info("Detected %d regions; OCR succeeded for %d/%d", len(regions),
                    sum(region.error_code is None for region in regions), len(regions))
        translation_start = perf_counter()
        candidates = [index for index, region in enumerate(regions)
                      if region.error_code is None and region.source_text and region.source_text.strip()]
        metrics.count("translation_candidates", len(candidates))
        metrics.count("translation_skipped", len(regions) - len(candidates) if translate else len(regions))
        metrics.count("duplicate_source_texts", len(candidates) - len({regions[index].source_text for index in candidates}))
        if translate and candidates:
            token = current_metrics.set(metrics)
            try:
                with metrics.stage("translation"):
                    translated = await run_in_threadpool(
                        self.translator.translate_batch,
                        [regions[index].source_text for index in candidates], "ja", target_language,
                    )
                if len(translated) != len(candidates):
                    raise ValueError("Translation batch length differs from OCR input")
                metrics.count("translation_failed", sum(item.error_code is not None for item in translated))
                for index, item in zip(candidates, translated):
                    regions[index] = replace(regions[index],
                                             translated_text=item.translated_text,
                                             translation_error_code=item.error_code)
            except Exception:
                metrics.count("translation_failed", len(candidates))
                logger.exception("Translation failed for %d regions", len(candidates))
                for index in candidates:
                    regions[index] = replace(regions[index],
                                             translation_error_code="TRANSLATION_FAILED")
            finally:
                current_metrics.reset(token)
        translation_ms = round((perf_counter() - translation_start) * 1000) if translate and candidates else 0
        return ProcessingResult(regions, detection_ms, ocr_ms, translation_ms)

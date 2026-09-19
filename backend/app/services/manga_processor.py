import asyncio
import logging
from dataclasses import dataclass
from time import perf_counter

from fastapi.concurrency import run_in_threadpool
from PIL import Image

from app.services.detection.base import DetectedRegion, TextDetector
from app.services.image_crops import crop_region
from app.services.ocr.base import OcrEngine

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class ProcessedRegion:
    id: str
    bbox: DetectedRegion
    source_text: str | None
    error_code: str | None = None


@dataclass(frozen=True)
class ProcessingResult:
    regions: list[ProcessedRegion]
    detection_ms: int
    ocr_ms: int


class DetectionFailed(Exception):
    pass


class MangaProcessor:
    def __init__(
        self,
        detector: TextDetector,
        ocr: OcrEngine,
        detector_lock: asyncio.Lock,
        ocr_lock: asyncio.Lock,
    ) -> None:
        self.detector = detector
        self.ocr = ocr
        self.detector_lock = detector_lock
        self.ocr_lock = ocr_lock

    async def process(self, image: Image.Image) -> ProcessingResult:
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
        return ProcessingResult(regions, detection_ms, ocr_ms)

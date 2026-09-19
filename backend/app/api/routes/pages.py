import io
import logging
from time import perf_counter

from fastapi import APIRouter, File, HTTPException, Request, UploadFile
from fastapi.concurrency import run_in_threadpool
from PIL import Image, ImageOps, UnidentifiedImageError
from pydantic import BaseModel

from app.services.detection.base import DetectedRegion

router = APIRouter()
logger = logging.getLogger(__name__)
MAX_BYTES = 25 * 1024 * 1024
MAX_PIXELS = 40_000_000
FORMATS = {"JPEG", "PNG", "WEBP"}


class BoxResponse(BaseModel):
    x: int
    y: int
    width: int
    height: int


class RegionResponse(BaseModel):
    id: str
    bbox: BoxResponse


class PageResponse(BaseModel):
    width: int
    height: int


class ProcessingResponse(BaseModel):
    detection_ms: int
    total_ms: int


class AnalysisResponse(BaseModel):
    page: PageResponse
    regions: list[RegionResponse]
    processing: ProcessingResponse


def decode_image(data: bytes) -> Image.Image:
    if not data or len(data) > MAX_BYTES:
        raise HTTPException(400, "Image is empty or exceeds 25 MB")
    try:
        with Image.open(io.BytesIO(data)) as image:
            if image.format not in FORMATS:
                raise HTTPException(415, "Supported formats: JPEG, PNG, WEBP")
            if image.width <= 0 or image.height <= 0 or image.width * image.height > MAX_PIXELS:
                raise HTTPException(400, "Image dimensions are invalid or too large")
            image.load()
            return ImageOps.exif_transpose(image).convert("RGB")
    except (UnidentifiedImageError, Image.DecompressionBombError, OSError, ValueError) as exc:
        raise HTTPException(400, "Invalid or corrupt image") from exc


@router.post("/pages/analyze", response_model=AnalysisResponse)
async def analyze_page(request: Request, image: UploadFile = File(...)) -> AnalysisResponse:
    start = perf_counter()
    if image.content_type not in {"image/jpeg", "image/png", "image/webp", "application/octet-stream"}:
        raise HTTPException(415, "Supported formats: JPEG, PNG, WEBP")
    data = await image.read(MAX_BYTES + 1)
    source = decode_image(data)
    detector = getattr(request.app.state, "detector", None)
    if detector is None:
        raise HTTPException(503, "Text detector is not ready")
    detection_start = perf_counter()
    try:
        async with request.app.state.detector_lock:
            regions: list[DetectedRegion] = await run_in_threadpool(detector.detect, source)
    except Exception as exc:
        logger.exception("Text detection failed")
        raise HTTPException(500, "Text detection failed") from exc
    detection_ms = round((perf_counter() - detection_start) * 1000)
    total_ms = round((perf_counter() - start) * 1000)
    logger.info("Detected %d regions in %d ms", len(regions), detection_ms)
    return AnalysisResponse(
        page=PageResponse(width=source.width, height=source.height),
        regions=[RegionResponse(id=f"region_{index:03d}", bbox=BoxResponse(**vars(region)))
                 for index, region in enumerate(regions, start=1)],
        processing=ProcessingResponse(detection_ms=detection_ms, total_ms=total_ms),
    )

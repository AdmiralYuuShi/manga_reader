import io
import logging
from time import perf_counter

from fastapi import APIRouter, File, HTTPException, Request, UploadFile
from PIL import Image, ImageOps, UnidentifiedImageError
from pydantic import BaseModel

from app.services.manga_processor import DetectionFailed, MangaProcessor

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


class RegionErrorResponse(BaseModel):
    code: str


class RegionResponse(BaseModel):
    id: str
    bbox: BoxResponse
    source_language: str = "ja"
    source_text: str | None
    error: RegionErrorResponse | None = None


class PageResponse(BaseModel):
    width: int
    height: int


class ProcessingResponse(BaseModel):
    detection_ms: int
    ocr_ms: int
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
    ocr = getattr(request.app.state, "ocr", None)
    if ocr is None:
        raise HTTPException(503, "Manga OCR is not ready")
    processor = MangaProcessor(detector, ocr, request.app.state.detector_lock,
                               request.app.state.ocr_lock)
    try:
        result = await processor.process(source)
    except DetectionFailed as exc:
        logger.exception("Text detection failed")
        raise HTTPException(500, "Text detection failed") from exc
    total_ms = round((perf_counter() - start) * 1000)
    return AnalysisResponse(
        page=PageResponse(width=source.width, height=source.height),
        regions=[RegionResponse(id=region.id, bbox=BoxResponse(**vars(region.bbox)),
                                source_text=region.source_text,
                                error=(RegionErrorResponse(code=region.error_code)
                                       if region.error_code else None))
                 for region in result.regions],
        processing=ProcessingResponse(detection_ms=result.detection_ms,
                                      ocr_ms=result.ocr_ms, total_ms=total_ms),
    )

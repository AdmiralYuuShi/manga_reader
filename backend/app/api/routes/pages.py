import io
import logging
from time import perf_counter

from fastapi import APIRouter, File, Form, HTTPException, Request, UploadFile
from fastapi.routing import APIRoute
from fastapi.exceptions import RequestValidationError
from PIL import Image, ImageOps, UnidentifiedImageError
from pydantic import BaseModel

from app.services.manga_processor import DetectionFailed, MangaProcessor
from app.services.performance import PerformanceMetrics

logger = logging.getLogger(__name__)


class ProfiledPageRoute(APIRoute):
    def get_route_handler(self):
        handler = super().get_route_handler()

        async def profile(request: Request):
            metrics = PerformanceMetrics()
            request.state.performance = metrics
            status = 500
            try:
                response = await handler(request)
                status = response.status_code
                if hasattr(request.state, "response_ready"):
                    metrics.stages["response_serialization"] = (
                        perf_counter() - request.state.response_ready
                    )
                return response
            except HTTPException as exc:
                status = exc.status_code
                raise
            except RequestValidationError:
                status = 422
                raise
            finally:
                logger.info(metrics.summary(perf_counter() - metrics.started, status))

        return profile


router = APIRouter(route_class=ProfiledPageRoute)
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
    target_language: str | None = None
    translated_text: str | None = None
    translation_error: RegionErrorResponse | None = None


class PageResponse(BaseModel):
    width: int
    height: int


class ProcessingResponse(BaseModel):
    detection_ms: int
    ocr_ms: int
    translation_ms: int
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
async def analyze_page(request: Request, image: UploadFile = File(...),
                       translate: bool = Form(True), target_language: str = Form("id")) -> AnalysisResponse:
    start = perf_counter()
    metrics: PerformanceMetrics = request.state.performance
    metrics.stages["form_parse"] = start - metrics.started
    if image.content_type not in {"image/jpeg", "image/png", "image/webp", "application/octet-stream"}:
        raise HTTPException(415, "Supported formats: JPEG, PNG, WEBP")
    with metrics.stage("upload_read"):
        data = await image.read(MAX_BYTES + 1)
    with metrics.stage("decode"):
        source = decode_image(data)
    logger.info("[PERF] image width=%d height=%d bytes=%d", source.width, source.height, len(data))
    detector = getattr(request.app.state, "detector", None)
    if detector is None:
        raise HTTPException(503, "Text detector is not ready")
    ocr = getattr(request.app.state, "ocr", None)
    if ocr is None:
        raise HTTPException(503, "Manga OCR is not ready")
    processor = MangaProcessor(detector, ocr, request.app.state.detector_lock,
                               request.app.state.ocr_lock, request.app.state.translator)
    try:
        result = await processor.process(source, translate=translate,
                                         target_language=target_language, metrics=metrics)
    except DetectionFailed as exc:
        logger.exception("Text detection failed")
        raise HTTPException(500, "Text detection failed") from exc
    total_ms = round((perf_counter() - start) * 1000)
    with metrics.stage("response_prepare"):
        response = AnalysisResponse(
            page=PageResponse(width=source.width, height=source.height),
            regions=[RegionResponse(id=region.id, bbox=BoxResponse(**vars(region.bbox)),
                                source_text=region.source_text,
                                error=(RegionErrorResponse(code=region.error_code)
                                       if region.error_code else None),
                                target_language=target_language if translate else None,
                                translated_text=region.translated_text,
                                translation_error=(RegionErrorResponse(code=region.translation_error_code)
                                                   if region.translation_error_code else None))
                 for region in result.regions],
            processing=ProcessingResponse(detection_ms=result.detection_ms,
                                          ocr_ms=result.ocr_ms,
                                          translation_ms=result.translation_ms, total_ms=total_ms),
        )
    request.state.response_ready = perf_counter()
    return response

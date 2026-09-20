import logging
import asyncio
from contextlib import asynccontextmanager
from time import perf_counter

from fastapi import FastAPI

from app.api.routes.health import router as health_router
from app.api.routes.pages import router as pages_router
from app.config import get_settings
from app.logging_config import configure_logging
from app.services.detection.comic_text_detector import ComicTextDetector
from app.services.device import resolve_device
from app.services.ocr.manga_ocr import MangaOcrEngine
from app.services.translation.factory import create_translator

settings = get_settings()
configure_logging(settings.log_level)
logger = logging.getLogger(__name__)


def log_cuda_memory(label: str) -> None:
    import torch

    if torch.cuda.is_available():
        torch.cuda.synchronize()
        logger.info("[PERF] %s cuda_allocated=%.1fMiB cuda_reserved=%.1fMiB",
                    label, torch.cuda.memory_allocated() / 1048576,
                    torch.cuda.memory_reserved() / 1048576)

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting Manga Translator backend")
    import torch

    device = resolve_device(settings.device, torch.cuda.is_available())
    logger.info("PyTorch %s CUDA runtime=%s available=%s selected=%s gpu=%s",
                torch.__version__, torch.version.cuda, torch.cuda.is_available(),
                device, torch.cuda.get_device_name(0) if torch.cuda.is_available() else "none")
    log_cuda_memory("before_models")
    app.state.detector = None
    app.state.detector_lock = asyncio.Lock()
    app.state.ocr = None
    app.state.ocr_lock = asyncio.Lock()
    app.state.translator = create_translator(settings)
    logger.info("Translation provider: %s", settings.translation_provider)
    try:
        started = perf_counter()
        app.state.detector = ComicTextDetector(settings.detector_source, settings.detector_model,
                                               settings.device)
        logger.info("[PERF] detector_startup=%.3fs device=%s input_size=%s",
                    perf_counter() - started, app.state.detector.device,
                    app.state.detector._model.input_size)
        log_cuda_memory("detector_loaded")
    except Exception:
        logger.exception("Text detector initialization failed; analysis is unavailable")
    try:
        started = perf_counter()
        app.state.ocr = MangaOcrEngine(settings.ocr_model, settings.device)
        logger.info("[PERF] ocr_startup=%.3fs device=%s",
                    perf_counter() - started, app.state.ocr.device)
        log_cuda_memory("models_loaded")
    except Exception:
        logger.exception("Manga OCR initialization failed; analysis is unavailable")
    yield


app = FastAPI(title="Manga Translator API", lifespan=lifespan)
app.include_router(health_router, prefix="/api/v1")
app.include_router(pages_router, prefix="/api/v1")

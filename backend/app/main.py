import logging
import asyncio
from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.api.routes.health import router as health_router
from app.api.routes.pages import router as pages_router
from app.config import get_settings
from app.logging_config import configure_logging
from app.services.detection.comic_text_detector import ComicTextDetector
from app.services.ocr.manga_ocr import MangaOcrEngine
from app.services.translation.factory import create_translator

settings = get_settings()
configure_logging(settings.log_level)
logger = logging.getLogger(__name__)

@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting Manga Translator backend")
    app.state.detector = None
    app.state.detector_lock = asyncio.Lock()
    app.state.ocr = None
    app.state.ocr_lock = asyncio.Lock()
    app.state.translator = create_translator(settings)
    try:
        app.state.detector = ComicTextDetector(settings.detector_source, settings.detector_model)
    except Exception:
        logger.exception("Text detector initialization failed; analysis is unavailable")
    try:
        app.state.ocr = MangaOcrEngine(settings.ocr_model)
    except Exception:
        logger.exception("Manga OCR initialization failed; analysis is unavailable")
    yield


app = FastAPI(title="Manga Translator API", lifespan=lifespan)
app.include_router(health_router, prefix="/api/v1")
app.include_router(pages_router, prefix="/api/v1")

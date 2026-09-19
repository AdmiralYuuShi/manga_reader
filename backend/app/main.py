import logging

from fastapi import FastAPI

from app.api.routes.health import router as health_router
from app.config import get_settings
from app.logging_config import configure_logging

settings = get_settings()
configure_logging(settings.log_level)
logger = logging.getLogger(__name__)

app = FastAPI(title="Manga Translator API")
app.include_router(health_router, prefix="/api/v1")


@app.on_event("startup")
def startup() -> None:
    logger.info("Starting Manga Translator backend")

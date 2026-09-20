import os
from dataclasses import dataclass
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent


@dataclass(frozen=True)
class Settings:
    host: str = "127.0.0.1"
    port: int = 8000
    log_level: str = "INFO"
    detector_source: Path = BACKEND_DIR / "vendor" / "comic-text-detector"
    detector_model: Path = BACKEND_DIR / "models" / "comictextdetector.pt"
    ocr_model: str = "kha-white/manga-ocr-base"
    device: str = "auto"
    translation_provider: str = "mymemory"
    translation_request_interval: float = 0.3
    translation_max_retries: int = 2
    translation_retry_initial_delay: float = 2.0


def get_settings() -> Settings:
    return Settings(
        host=os.getenv("MANGA_BACKEND_HOST", "127.0.0.1"),
        port=int(os.getenv("MANGA_BACKEND_PORT", "8000")),
        log_level=os.getenv("MANGA_LOG_LEVEL", "INFO").upper(),
        detector_source=Path(os.getenv("MANGA_DETECTOR_SOURCE", str(BACKEND_DIR / "vendor" / "comic-text-detector"))),
        detector_model=Path(os.getenv("MANGA_DETECTOR_MODEL", str(BACKEND_DIR / "models" / "comictextdetector.pt"))),
        ocr_model=os.getenv("MANGA_OCR_MODEL", "kha-white/manga-ocr-base"),
        device=os.getenv("MANGA_DEVICE", "auto").lower(),
        translation_provider=os.getenv("MANGA_TRANSLATION_PROVIDER", "mymemory").lower(),
        translation_request_interval=float(os.getenv("MANGA_TRANSLATION_REQUEST_INTERVAL", "0.3")),
        translation_max_retries=int(os.getenv("MANGA_TRANSLATION_MAX_RETRIES", "2")),
        translation_retry_initial_delay=float(os.getenv("MANGA_TRANSLATION_RETRY_INITIAL_DELAY", "2")),
    )

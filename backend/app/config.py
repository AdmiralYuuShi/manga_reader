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


def get_settings() -> Settings:
    return Settings(
        host=os.getenv("MANGA_BACKEND_HOST", "127.0.0.1"),
        port=int(os.getenv("MANGA_BACKEND_PORT", "8000")),
        log_level=os.getenv("MANGA_LOG_LEVEL", "INFO").upper(),
        detector_source=Path(os.getenv("MANGA_DETECTOR_SOURCE", str(BACKEND_DIR / "vendor" / "comic-text-detector"))),
        detector_model=Path(os.getenv("MANGA_DETECTOR_MODEL", str(BACKEND_DIR / "models" / "comictextdetector.pt"))),
    )

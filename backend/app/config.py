import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    host: str = "127.0.0.1"
    port: int = 8000
    log_level: str = "INFO"


def get_settings() -> Settings:
    return Settings(
        host=os.getenv("MANGA_BACKEND_HOST", "127.0.0.1"),
        port=int(os.getenv("MANGA_BACKEND_PORT", "8000")),
        log_level=os.getenv("MANGA_LOG_LEVEL", "INFO").upper(),
    )

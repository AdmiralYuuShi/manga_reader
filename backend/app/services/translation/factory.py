from app.config import Settings
from app.services.translation.base import Translator
from app.services.translation.google import GoogleTranslationService
from app.services.translation.mymemory import MyMemoryTranslator


def create_translator(settings: Settings) -> Translator:
    if settings.translation_provider == "mymemory":
        return MyMemoryTranslator()
    if settings.translation_provider == "google":
        return GoogleTranslationService(
            request_interval=settings.translation_request_interval,
            max_retries=settings.translation_max_retries,
            retry_initial_delay=settings.translation_retry_initial_delay,
        )
    raise ValueError(f"Unsupported translation provider: {settings.translation_provider}")

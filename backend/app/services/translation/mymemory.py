"""MyMemory translation with application-to-provider language mapping."""

import logging

from deep_translator import MyMemoryTranslator as DeepMyMemoryTranslator
from deep_translator.constants import MY_MEMORY_LANGUAGES_TO_CODES

from app.services.translation.base import TranslationItem

logger = logging.getLogger(__name__)

LANGUAGE_CODES = {
    "ja": MY_MEMORY_LANGUAGES_TO_CODES["japanese"],
    "id": MY_MEMORY_LANGUAGES_TO_CODES["indonesian"],
}


class MyMemoryTranslator:
    def _language(self, code: str) -> str:
        try:
            return LANGUAGE_CODES[code]
        except KeyError as exc:
            raise ValueError(f"MyMemory does not support application language '{code}'") from exc

    def translate(self, text: str, source_language: str, target_language: str) -> str:
        source = self._language(source_language)
        target = self._language(target_language)
        result = DeepMyMemoryTranslator(source=source, target=target).translate(text)
        if not isinstance(result, str) or not result.strip():
            raise ValueError("MyMemory returned no translation")
        return result

    def translate_batch(
        self, texts: list[str], source_language: str, target_language: str
    ) -> list[TranslationItem]:
        logger.info("Translating %d regions using MyMemory", len(texts))
        results = []
        successes = 0
        try:
            source = self._language(source_language)
            target = self._language(target_language)
            provider = DeepMyMemoryTranslator(source=source, target=target)
        except Exception as exc:
            logger.warning("MyMemory translation setup failed: %s", type(exc).__name__)
            return [TranslationItem(error_code="TRANSLATION_FAILED") if text and text.strip()
                    else TranslationItem() for text in texts]
        for index, text in enumerate(texts, start=1):
            if not text or not text.strip():
                results.append(TranslationItem())
                continue
            try:
                translated = provider.translate(text)
                if not isinstance(translated, str) or not translated.strip():
                    raise ValueError("MyMemory returned no translation")
                results.append(TranslationItem(translated_text=translated))
                successes += 1
            except Exception as exc:
                logger.warning("MyMemory translation %d/%d failed: %s", index, len(texts),
                               type(exc).__name__)
                results.append(TranslationItem(error_code="TRANSLATION_FAILED"))
        logger.info("Translation completed: %d/%d", successes, len(texts))
        return results

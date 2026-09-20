"""Rate-limited Google translation behind the application's batch interface."""

import logging
import threading
import time

from deep_translator import GoogleTranslator
from deep_translator.exceptions import TooManyRequests

from app.services.translation.base import TranslationItem
from app.services.performance import current_metrics

logger = logging.getLogger(__name__)


class GoogleTranslationService:
    def __init__(self, request_interval: float = 0.3, max_retries: int = 2,
                 retry_initial_delay: float = 2.0) -> None:
        if request_interval < 0 or max_retries < 0 or retry_initial_delay < 0:
            raise ValueError("Translation timing and retry settings must be nonnegative")
        self.request_interval = request_interval
        self.max_retries = max_retries
        self.retry_initial_delay = retry_initial_delay
        self._request_lock = threading.Lock()
        self._next_request_at = 0.0

    def _request(self, text: str, source_language: str, target_language: str) -> str:
        # The service is shared by requests. Reserve each request start under one lock.
        with self._request_lock:
            remaining = self._next_request_at - time.monotonic()
            if remaining > 0:
                time.sleep(remaining)
            self._next_request_at = time.monotonic() + self.request_interval
        metrics = current_metrics.get()
        started = time.perf_counter()
        if metrics is not None:
            metrics.count("translation_requests")
        try:
            result = GoogleTranslator(source=source_language, target=target_language).translate(text)
        finally:
            if metrics is not None:
                metrics.add_detail("provider_request_time", time.perf_counter() - started)
        if not isinstance(result, str):
            raise ValueError("Translation provider returned no text")
        return result

    def translate(self, text: str, source_language: str, target_language: str) -> str:
        for retry in range(self.max_retries + 1):
            try:
                return self._request(text, source_language, target_language)
            except TooManyRequests:
                if retry == self.max_retries:
                    raise
                delay = self.retry_initial_delay * (2 ** retry)
                logger.warning("Google translation rate limited; retrying in %.1fs", delay)
                time.sleep(delay)
        raise AssertionError("Unreachable retry state")

    def translate_batch(
        self, texts: list[str], source_language: str, target_language: str
    ) -> list[TranslationItem]:
        logger.info("Translating %d regions using Google", len(texts))
        results = []
        successes = 0
        for index, text in enumerate(texts, start=1):
            if not text or not text.strip():
                results.append(TranslationItem())
                continue
            try:
                translated = self.translate(text, source_language, target_language)
                results.append(TranslationItem(translated_text=translated))
                successes += 1
                logger.info("Translation %d/%d succeeded", index, len(texts))
            except TooManyRequests:
                logger.warning("Translation %d/%d failed after rate-limit retries", index, len(texts))
                results.append(TranslationItem(error_code="TRANSLATION_FAILED"))
            except Exception:
                logger.exception("Translation %d/%d failed", index, len(texts))
                results.append(TranslationItem(error_code="TRANSLATION_FAILED"))
        logger.info("Translation completed: %d/%d", successes, len(texts))
        return results

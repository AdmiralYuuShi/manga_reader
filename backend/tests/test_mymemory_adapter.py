from dataclasses import replace

import pytest

from app.config import get_settings
from app.services.translation.base import TranslationItem
from app.services.translation.factory import create_translator
from app.services.translation.google import GoogleTranslationService
from app.services.translation.mymemory import MyMemoryTranslator


def test_single_translation_maps_application_languages(monkeypatch):
    calls = []

    class FakeProvider:
        def __init__(self, source, target):
            calls.append((source, target))

        def translate(self, text):
            calls.append(text)
            return "Hari ini kamu pergi ke sekolah?"

    monkeypatch.setattr("app.services.translation.mymemory.DeepMyMemoryTranslator", FakeProvider)
    result = MyMemoryTranslator().translate("今日は学校に行くの？", "ja", "id")
    assert result == "Hari ini kamu pergi ke sekolah?"
    assert calls == [("ja-JP", "id-ID"), "今日は学校に行くの？"]


def test_order_partial_failure_and_empty_text(monkeypatch):
    calls = []

    class FakeProvider:
        def __init__(self, source, target):
            calls.append((source, target))

        def translate(self, text):
            calls.append(text)
            if text == "bad":
                raise RuntimeError("service unavailable")
            return f"translated {text}"

    monkeypatch.setattr("app.services.translation.mymemory.DeepMyMemoryTranslator", FakeProvider)
    result = MyMemoryTranslator().translate_batch(
        ["first", "", "bad", "  ", "last"], "ja", "id"
    )
    assert result == [TranslationItem("translated first"), TranslationItem(),
                      TranslationItem(error_code="TRANSLATION_FAILED"), TranslationItem(),
                      TranslationItem("translated last")]
    assert calls == [("ja-JP", "id-ID"), "first", "bad", "last"]


def test_unsupported_language_fails_without_provider_request(monkeypatch):
    def forbidden(*args, **kwargs):
        raise AssertionError("Provider must not be called")

    monkeypatch.setattr("app.services.translation.mymemory.DeepMyMemoryTranslator", forbidden)
    service = MyMemoryTranslator()
    with pytest.raises(ValueError, match="does not support"):
        service.translate("hello", "ja", "en")
    assert service.translate_batch(["text", ""], "ja", "en") == [
        TranslationItem(error_code="TRANSLATION_FAILED"), TranslationItem()
    ]


def test_empty_provider_result_is_local_failure(monkeypatch):
    class FakeProvider:
        def __init__(self, source, target):
            pass

        def translate(self, text):
            return " " if text == "bad" else "good"

    monkeypatch.setattr("app.services.translation.mymemory.DeepMyMemoryTranslator", FakeProvider)
    assert MyMemoryTranslator().translate_batch(["bad", "ok"], "ja", "id") == [
        TranslationItem(error_code="TRANSLATION_FAILED"), TranslationItem("good")
    ]


def test_provider_selection_and_default(monkeypatch):
    monkeypatch.delenv("MANGA_TRANSLATION_PROVIDER", raising=False)
    settings = get_settings()
    assert settings.translation_provider == "mymemory"
    assert isinstance(create_translator(settings), MyMemoryTranslator)
    assert isinstance(create_translator(replace(settings, translation_provider="google")),
                      GoogleTranslationService)
    with pytest.raises(ValueError, match="Unsupported translation provider"):
        create_translator(replace(settings, translation_provider="unknown"))
    monkeypatch.setenv("MANGA_TRANSLATION_PROVIDER", "GOOGLE")
    assert get_settings().translation_provider == "google"

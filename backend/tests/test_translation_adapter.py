import pytest
from deep_translator.exceptions import TooManyRequests

from app.services.translation.base import TranslationItem
from app.services.translation.google import GoogleTranslationService


class FakeClock:
    def __init__(self):
        self.now = 10.0
        self.sleeps = []

    def monotonic(self):
        return self.now

    def sleep(self, seconds):
        self.sleeps.append(seconds)
        self.now += seconds


@pytest.fixture
def clock(monkeypatch):
    fake = FakeClock()
    monkeypatch.setattr("app.services.translation.google.time.monotonic", fake.monotonic)
    monkeypatch.setattr("app.services.translation.google.time.sleep", fake.sleep)
    return fake


def test_order_delay_and_empty_text(monkeypatch, clock):
    calls = []

    class FakeGoogleTranslator:
        def __init__(self, source, target):
            assert (source, target) == ("ja", "id")

        def translate(self, text):
            calls.append((text, clock.now))
            return f"translated {text}"

    monkeypatch.setattr("app.services.translation.google.GoogleTranslator", FakeGoogleTranslator)
    service = GoogleTranslationService(request_interval=0.3)
    result = service.translate_batch(["first", "", "  ", "second", "third"], "ja", "id")
    assert result == [TranslationItem("translated first"), TranslationItem(),
                      TranslationItem(), TranslationItem("translated second"),
                      TranslationItem("translated third")]
    assert [text for text, _ in calls] == ["first", "second", "third"]
    assert [when for _, when in calls] == pytest.approx([10.0, 10.3, 10.6])
    assert clock.sleeps == pytest.approx([0.3, 0.3])


def test_rate_limit_retries_then_succeeds(monkeypatch, clock):
    calls = []

    class FakeGoogleTranslator:
        def __init__(self, source, target):
            pass

        def translate(self, text):
            calls.append(clock.now)
            if len(calls) < 3:
                raise TooManyRequests()
            return "success"

    monkeypatch.setattr("app.services.translation.google.GoogleTranslator", FakeGoogleTranslator)
    result = GoogleTranslationService().translate_batch(["text"], "ja", "id")
    assert result == [TranslationItem("success")]
    assert calls == pytest.approx([10.0, 12.0, 16.0])
    assert clock.sleeps == [2.0, 4.0]


def test_exhausted_retry_is_local_failure(monkeypatch, clock):
    calls = []

    class FakeGoogleTranslator:
        def __init__(self, source, target):
            pass

        def translate(self, text):
            calls.append((text, clock.now))
            if text == "bad":
                raise TooManyRequests()
            return f"translated {text}"

    monkeypatch.setattr("app.services.translation.google.GoogleTranslator", FakeGoogleTranslator)
    result = GoogleTranslationService().translate_batch(["first", "bad", "last"], "ja", "id")
    assert result == [TranslationItem("translated first"),
                      TranslationItem(error_code="TRANSLATION_FAILED"),
                      TranslationItem("translated last")]
    assert [text for text, _ in calls] == ["first", "bad", "bad", "bad", "last"]
    assert clock.sleeps == pytest.approx([0.3, 2.0, 4.0, 0.3])


def test_non_rate_limit_error_is_not_retried(monkeypatch, clock):
    calls = []

    class FakeGoogleTranslator:
        def __init__(self, source, target):
            pass

        def translate(self, text):
            calls.append(text)
            raise ValueError("permanent error")

    monkeypatch.setattr("app.services.translation.google.GoogleTranslator", FakeGoogleTranslator)
    result = GoogleTranslationService().translate_batch(["bad"], "ja", "id")
    assert result == [TranslationItem(error_code="TRANSLATION_FAILED")]
    assert calls == ["bad"]
    assert clock.sleeps == []


def test_invalid_settings():
    with pytest.raises(ValueError):
        GoogleTranslationService(max_retries=-1)

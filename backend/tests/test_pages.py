import io

from fastapi.testclient import TestClient
from PIL import Image
import pytest

from app.main import app
from app.services.detection.base import DetectedRegion
from app.services.detection.comic_text_detector import normalize_box
from app.services.translation.base import TranslationItem


@pytest.fixture(autouse=True)
def no_model_startup(monkeypatch):
    def unavailable(*args):
        raise FileNotFoundError("model omitted in unit tests")

    monkeypatch.setattr("app.main.ComicTextDetector", unavailable)
    monkeypatch.setattr("app.main.MangaOcrEngine", unavailable)


class FakeDetector:
    def __init__(self, regions):
        self.regions = regions

    def detect(self, image):
        assert image.size == (20, 10)
        return self.regions


class FailingDetector:
    def detect(self, image):
        raise RuntimeError("private failure")


class FakeOcr:
    def recognize(self, image):
        return "今日は"


class FailingOcr:
    def recognize(self, image):
        raise RuntimeError("private OCR failure")


class FakeTranslator:
    def translate_batch(self, texts, source_language, target_language):
        return [TranslationItem(translated_text="Hari ini") for _ in texts]


def image_bytes():
    stream = io.BytesIO()
    Image.new("RGB", (20, 10), "white").save(stream, format="PNG")
    return stream.getvalue()


def test_normalize_box_clips_original_coordinates():
    assert normalize_box([-5, 2, 25, 12], 20, 10) == DetectedRegion(0, 2, 20, 8)
    assert normalize_box([30, 0, 40, 5], 20, 10) is None


def test_empty_detection_is_success():
    with TestClient(app) as client:
        app.state.detector = FakeDetector([])
        app.state.ocr = FakeOcr()
        app.state.translator = FakeTranslator()
        response = client.post("/api/v1/pages/analyze", files={"image": ("page.png", image_bytes(), "image/png")})
        assert response.status_code == 200
        assert response.json()["page"] == {"width": 20, "height": 10}
        assert response.json()["regions"] == []
        assert response.json()["processing"]["total_ms"] >= 0


def test_region_serialization_and_health():
    with TestClient(app) as client:
        assert client.get("/api/v1/health").json()["detector_ready"] is False
        app.state.detector = FakeDetector([DetectedRegion(1, 2, 3, 4)])
        app.state.ocr = FakeOcr()
        app.state.translator = FakeTranslator()
        assert client.get("/api/v1/health").json() == {
            "status": "ok", "detector_ready": True, "ocr_ready": True
        }
        response = client.post("/api/v1/pages/analyze", files={"image": ("page.png", image_bytes(), "image/png")})
        region = response.json()["regions"][0]
        assert region["id"] == "region_001"
        assert region["target_language"] == "id"
        assert region["translated_text"] == "Hari ini"
        assert region["translation_error"] is None
        assert response.json()["processing"]["ocr_ms"] >= 0
        assert response.json()["processing"]["translation_ms"] >= 0


def test_invalid_image_and_unavailable_detector():
    with TestClient(app) as client:
        app.state.detector = FakeDetector([])
        app.state.ocr = FakeOcr()
        response = client.post("/api/v1/pages/analyze", files={"image": ("bad.png", b"garbage", "image/png")})
        assert response.status_code == 400
        app.state.detector = None
        response = client.post("/api/v1/pages/analyze", files={"image": ("page.png", image_bytes(), "image/png")})
        assert response.status_code == 503


def test_detector_failure_does_not_expose_exception():
    with TestClient(app) as client:
        app.state.detector = FailingDetector()
        app.state.ocr = FakeOcr()
        response = client.post("/api/v1/pages/analyze", files={"image": ("page.png", image_bytes(), "image/png")})
        assert response.status_code == 500
        assert response.json()["detail"] == "Text detection failed"


def test_ocr_unavailable_returns_503():
    with TestClient(app) as client:
        app.state.detector = FakeDetector([])
        response = client.post("/api/v1/pages/analyze", files={"image": ("page.png", image_bytes(), "image/png")})
        assert response.status_code == 503
        assert response.json()["detail"] == "Manga OCR is not ready"


def test_ocr_error_is_serialized_per_region():
    with TestClient(app) as client:
        app.state.detector = FakeDetector([DetectedRegion(1, 2, 3, 4)])
        app.state.ocr = FailingOcr()
        response = client.post("/api/v1/pages/analyze", files={"image": ("page.png", image_bytes(), "image/png")})
        assert response.status_code == 200
        region = response.json()["regions"][0]
        assert region["source_text"] is None
        assert region["error"] == {"code": "OCR_FAILED"}


def test_translation_disabled_and_target_language():
    with TestClient(app) as client:
        app.state.detector = FakeDetector([DetectedRegion(1, 2, 3, 4)])
        app.state.ocr = FakeOcr()
        app.state.translator = FakeTranslator()
        files = {"image": ("page.png", image_bytes(), "image/png")}
        disabled = client.post("/api/v1/pages/analyze", files=files,
                               data={"translate": "false", "target_language": "en"})
        assert disabled.status_code == 200
        region = disabled.json()["regions"][0]
        assert region["source_text"]
        assert region["target_language"] is None
        assert region["translated_text"] is None
        assert disabled.json()["processing"]["translation_ms"] == 0
        enabled = client.post("/api/v1/pages/analyze", files=files,
                              data={"translate": "true", "target_language": "en"})
        assert enabled.json()["regions"][0]["target_language"] == "en"

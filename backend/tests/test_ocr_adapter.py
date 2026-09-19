import sys
from types import SimpleNamespace

from PIL import Image

from app.services.ocr.manga_ocr import MangaOcrEngine


def test_adapter_initializes_once_and_passes_pil_crops(monkeypatch):
    constructed = []

    class FakeMangaOcr:
        def __init__(self, pretrained_model_name_or_path):
            constructed.append(pretrained_model_name_or_path)
            self.model = SimpleNamespace(device="cpu")

        def __call__(self, image):
            assert isinstance(image, Image.Image)
            assert image.size == (4, 5)
            return "日本語"

    monkeypatch.setitem(sys.modules, "manga_ocr", SimpleNamespace(MangaOcr=FakeMangaOcr))
    engine = MangaOcrEngine("local-model")
    assert engine.device == "cpu"
    assert engine.recognize(Image.new("RGB", (4, 5))) == "日本語"
    assert engine.recognize(Image.new("RGB", (4, 5))) == "日本語"
    assert constructed == ["local-model"]

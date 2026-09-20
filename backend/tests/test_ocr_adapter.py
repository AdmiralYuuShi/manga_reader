import sys
from types import SimpleNamespace

from PIL import Image

from app.services.ocr.manga_ocr import MangaOcrEngine


def test_adapter_initializes_once_and_passes_pil_crops(monkeypatch):
    import torch

    monkeypatch.setattr(torch.cuda, "is_available", lambda: False)
    constructed = []

    class FakeMangaOcr:
        def __init__(self, pretrained_model_name_or_path, force_cpu=False):
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


def test_explicit_cpu_uses_upstream_force_cpu(monkeypatch):
    calls = []

    class FakeMangaOcr:
        def __init__(self, pretrained_model_name_or_path, force_cpu=False):
            calls.append(force_cpu)
            self.model = SimpleNamespace(device="cpu")

    monkeypatch.setitem(sys.modules, "manga_ocr", SimpleNamespace(MangaOcr=FakeMangaOcr))
    engine = MangaOcrEngine("local-model", device="cpu")
    assert engine.device == "cpu"
    assert calls == [True]

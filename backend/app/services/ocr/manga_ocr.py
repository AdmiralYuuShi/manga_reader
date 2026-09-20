import logging

from PIL import Image

from app.services.ocr.base import OcrEngine
from app.services.device import resolve_device

logger = logging.getLogger(__name__)


class MangaOcrEngine(OcrEngine):
    def __init__(self, model_name: str = "kha-white/manga-ocr-base", device: str = "auto") -> None:
        from manga_ocr import MangaOcr
        import torch

        logger.info("Loading manga-ocr model %s", model_name)
        chosen = resolve_device(device, torch.cuda.is_available())
        # Keep upstream automatic CUDA selection; force_cpu is its supported CPU path.
        if chosen == "cpu":
            self._model = MangaOcr(pretrained_model_name_or_path=model_name,
                                   force_cpu=True)
        else:
            self._model = MangaOcr(pretrained_model_name_or_path=model_name)
        self.device = str(self._model.model.device)
        if self.device.split(":")[0] != chosen:
            raise RuntimeError(f"OCR parameter placement mismatch: expected {chosen}, got {self.device}")
        logger.info("manga-ocr ready on %s", self.device)

    def recognize(self, image: Image.Image) -> str:
        return self._model(image)

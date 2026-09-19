import logging

from PIL import Image

from app.services.ocr.base import OcrEngine

logger = logging.getLogger(__name__)


class MangaOcrEngine(OcrEngine):
    def __init__(self, model_name: str = "kha-white/manga-ocr-base") -> None:
        from manga_ocr import MangaOcr

        logger.info("Loading manga-ocr model %s", model_name)
        # MangaOcr selects CUDA when available and falls back to CPU itself.
        self._model = MangaOcr(pretrained_model_name_or_path=model_name)
        self.device = str(self._model.model.device)
        logger.info("manga-ocr ready on %s", self.device)

    def recognize(self, image: Image.Image) -> str:
        return self._model(image)

from abc import ABC, abstractmethod

from PIL import Image


class OcrEngine(ABC):
    @abstractmethod
    def recognize(self, image: Image.Image) -> str:
        """Recognize Japanese text in one crop."""

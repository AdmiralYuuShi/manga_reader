from abc import ABC, abstractmethod
from dataclasses import dataclass

from PIL import Image


@dataclass(frozen=True)
class DetectedRegion:
    x: int
    y: int
    width: int
    height: int


class TextDetector(ABC):
    @abstractmethod
    def detect(self, image: Image.Image) -> list[DetectedRegion]:
        """Return regions in original image pixel coordinates."""

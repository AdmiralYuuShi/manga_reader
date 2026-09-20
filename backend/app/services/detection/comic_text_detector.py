import logging
import sys
from pathlib import Path

from PIL import Image

from app.services.detection.base import DetectedRegion, TextDetector
from app.services.device import resolve_device

logger = logging.getLogger(__name__)


def normalize_box(xyxy: list[int], width: int, height: int) -> DetectedRegion | None:
    """Clip an upstream xyxy box to the source image and discard empty boxes."""
    x1, y1, x2, y2 = (int(value) for value in xyxy)
    x1, x2 = max(0, min(width, x1)), max(0, min(width, x2))
    y1, y2 = max(0, min(height, y1)), max(0, min(height, y2))
    if x2 <= x1 or y2 <= y1:
        return None
    return DetectedRegion(x1, y1, x2 - x1, y2 - y1)


class ComicTextDetector(TextDetector):
    def __init__(self, source: Path, model_path: Path, device: str = "auto") -> None:
        if not (source / "inference.py").is_file():
            raise FileNotFoundError(f"Detector source missing: {source}")
        if not model_path.is_file():
            raise FileNotFoundError(f"Detector model missing: {model_path}")

        # Upstream uses absolute imports (basemodel, utils.*) from its root.
        sys.path.insert(0, str(source.resolve()))
        import torch
        from inference import TextDetector as UpstreamTextDetector

        self.device = resolve_device(device, torch.cuda.is_available())
        logger.info("Loading comic-text-detector on %s from %s", self.device, model_path)
        self._model = UpstreamTextDetector(
            model_path=str(model_path), input_size=1024, device=self.device, act="leaky"
        )
        model_devices = {parameter.device.type for parameter in self._model.net.parameters()}
        if model_devices != {self.device}:
            raise RuntimeError(f"Detector parameter placement mismatch: {model_devices}")
        logger.info("comic-text-detector ready")

    def detect(self, image: Image.Image) -> list[DetectedRegion]:
        import cv2
        import numpy as np

        # Upstream expects BGR and maps its own 1024px inference output to this input size.
        bgr = cv2.cvtColor(np.asarray(image.convert("RGB")), cv2.COLOR_RGB2BGR)
        _, _, blocks = self._model(bgr)
        regions = [normalize_box(block.xyxy, image.width, image.height) for block in blocks]
        return [region for region in regions if region is not None]

"""Start the configured backend and verify health over HTTP."""

import json
import io
import os
import subprocess
import sys
import time
from pathlib import Path
from urllib.request import urlopen
from urllib.request import Request

from PIL import Image, ImageOps


if __name__ == "__main__":
    backend = Path(__file__).resolve().parents[1]
    environment = os.environ.copy()
    environment["MANGA_BACKEND_PORT"] = "8765"
    process = subprocess.Popen(
        [sys.executable, "run.py"], cwd=backend, env=environment,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        result = None
        for _ in range(60):
            try:
                with urlopen("http://127.0.0.1:8765/api/v1/health", timeout=2) as response:
                    result = json.load(response)
                break
            except OSError:
                time.sleep(0.5)
        assert result == {"status": "ok", "detector_ready": True, "ocr_ready": True}, result
        print(result)
        if len(sys.argv) > 1:
            image_path = Path(sys.argv[1])
            image_data = image_path.read_bytes()
            with Image.open(io.BytesIO(image_data)) as source:
                expected_size = ImageOps.exif_transpose(source).size
            image_type = "image/jpeg" if image_path.suffix.lower() in {".jpg", ".jpeg"} else "image/png"
            filename = image_path.name
        else:
            image = io.BytesIO()
            Image.new("RGB", (256, 384), "white").save(image, format="PNG")
            image_data = image.getvalue()
            expected_size = (256, 384)
            image_type = "image/png"
            filename = "blank.png"
        boundary = "manga-smoke-boundary"
        body = (
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"image\"; filename=\"{filename}\"\r\n"
            f"Content-Type: {image_type}\r\n\r\n"
        ).encode() + image_data + f"\r\n--{boundary}--\r\n".encode()
        upload = Request(
            "http://127.0.0.1:8765/api/v1/pages/analyze", data=body,
            headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        )
        with urlopen(upload, timeout=1200) as response:
            analysis = json.load(response)
        assert analysis["page"] == {"width": expected_size[0], "height": expected_size[1]}
        assert isinstance(analysis["regions"], list)
        nonempty = sum(bool(region.get("source_text")) for region in analysis["regions"])
        print(f"HTTP inference: {len(analysis['regions'])} regions, {nonempty} non-empty OCR; "
              f"timings: {analysis['processing']}")
    finally:
        process.terminate()
        process.wait(timeout=10)

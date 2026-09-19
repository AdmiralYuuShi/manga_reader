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

from PIL import Image


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
        assert result == {"status": "ok", "detector_ready": True, "ocr_ready": False}, result
        print(result)
        image = io.BytesIO()
        Image.new("RGB", (256, 384), "white").save(image, format="PNG")
        boundary = "manga-smoke-boundary"
        body = (
            f"--{boundary}\r\nContent-Disposition: form-data; name=\"image\"; filename=\"blank.png\"\r\n"
            "Content-Type: image/png\r\n\r\n"
        ).encode() + image.getvalue() + f"\r\n--{boundary}--\r\n".encode()
        upload = Request(
            "http://127.0.0.1:8765/api/v1/pages/analyze", data=body,
            headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        )
        with urlopen(upload, timeout=180) as response:
            analysis = json.load(response)
        assert analysis["page"] == {"width": 256, "height": 384}
        assert isinstance(analysis["regions"], list)
        print(f"Blank-image HTTP inference: {len(analysis['regions'])} regions")
    finally:
        process.terminate()
        process.wait(timeout=10)

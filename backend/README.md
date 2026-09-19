# Backend setup (Windows PowerShell)

From the `backend` directory, create the environment and install dependencies:

```powershell
py -3.10 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

Get the official detector source and model. The clone and weights are ignored by Git:

```powershell
git clone https://github.com/dmMaze/comic-text-detector.git vendor/comic-text-detector
New-Item -ItemType Directory -Force models
Invoke-WebRequest -Uri 'https://github.com/zyddnys/manga-image-translator/releases/download/beta-0.2.1/comictextdetector.pt' -OutFile 'models/comictextdetector.pt'
```

The integration was checked against upstream commit `440b978563c71b758e31aaa315d100faba1efa2f`. Start the server:

```powershell
python run.py
```

If PowerShell blocks activation, run `.\.venv\Scripts\python.exe -m pip install -r requirements.txt` and `.\.venv\Scripts\python.exe run.py` directly.

The server listens on `http://127.0.0.1:8000` by default. Open `http://127.0.0.1:8000/api/v1/health` to check it. `detector_ready` and `ocr_ready` each become `true` after their respective models initialize. On first startup, manga-ocr downloads its official model (about 400 MB) to the Hugging Face cache. If either model fails, the server stays up and analysis returns HTTP 503. Configure `MANGA_BACKEND_HOST`, `MANGA_BACKEND_PORT`, `MANGA_LOG_LEVEL`, `MANGA_DETECTOR_SOURCE`, `MANGA_DETECTOR_MODEL`, and optionally `MANGA_OCR_MODEL` through environment variables.

`POST /api/v1/pages/analyze` accepts a multipart `image` field (JPEG, PNG, or WebP, up to 25 MB and 40 million pixels). It returns page dimensions, original-image pixel bounding boxes, Japanese `source_text` for each region, and separate detection/OCR timings. An empty OCR result is `""`; a failed region has `source_text: null` and an error code while other regions continue. OCR crops come from the decoded full-resolution image. They use no fixed padding because Mokuro uses line-specific transforms rather than a universal box expansion. For tests, install `requirements-dev.txt`, then run `.\.venv\Scripts\python.exe -m pytest` from this directory. Ordinary tests use fake models and do not load weights.

For a real-model HTTP smoke check, run `.\.venv\Scripts\python.exe tests/live_health.py`. This uses a synthetic blank image to verify the inference path. For detector, crop, and OCR on the upstream manga example, run `.\.venv\Scripts\python.exe tests/model_smoke.py vendor\comic-text-detector\data\examples\AisazuNihaIrarenai-003.jpg`. Pass that same image path to `tests/live_health.py` to analyze the entire page over HTTP.

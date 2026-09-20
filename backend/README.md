# Backend setup (Windows PowerShell)

For M15 stage timing logs, the measured CPU baseline, and a repeatable
before/after benchmark procedure, see [PERFORMANCE.md](PERFORMANCE.md).
CUDA-capable PyTorch is an optional separate installation after the regular
requirements; see the Phase B section there. `MANGA_DEVICE=auto` selects CUDA
when available and otherwise uses CPU. Set `MANGA_DEVICE=cpu` for a CPU
comparison or `MANGA_DEVICE=cuda` to require CUDA explicitly.

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

`POST /api/v1/pages/analyze` accepts multipart `image` (JPEG, PNG, or WebP, up to 25 MB and 40 million pixels), `translate` (boolean, default `true`), and `target_language` (default `id`). It returns page dimensions, original-image pixel bounding boxes, Japanese `source_text`, `target_language`, `translated_text`, and separate detection/OCR/translation timings. An empty OCR result is `""`; failed OCR has `source_text: null` and an `error` code. Translation is attempted only for nonempty OCR. Failed translation preserves `source_text`, sets `translated_text: null`, and reports `translation_error.code: TRANSLATION_FAILED` for that region while other translations continue. Set `translate=false` for OCR only.

Translation defaults to MyMemory (`MANGA_TRANSLATION_PROVIDER=mymemory`). The API uses `ja` and `id`; the MyMemory adapter maps these to its supported `ja-JP` and `id-ID` codes. Other application language codes currently fail per region without contacting MyMemory. MyMemory requests run sequentially in a worker thread, with no automatic retries or artificial delay. Set `MANGA_TRANSLATION_PROVIDER=google` to use the existing Google adapter. Its settings are `MANGA_TRANSLATION_REQUEST_INTERVAL` (default 0.3 seconds), `MANGA_TRANSLATION_MAX_RETRIES` (default 2), and `MANGA_TRANSLATION_RETRY_INITIAL_DELAY` (default 2 seconds). Both providers need internet access. MyMemory was reachable in a small Japanese-to-Indonesian smoke test, but translation quality varied; neither unofficial provider guarantees availability or accurate manga translation. OCR crops come from the decoded full-resolution image. They use no fixed padding because Mokuro uses line-specific transforms rather than a universal box expansion. For tests, install `requirements-dev.txt`, then run `.\.venv\Scripts\python.exe -m pytest` from this directory. Ordinary tests use fake models and fake translation, with no external requests.

For a real-model HTTP smoke check, run `.\.venv\Scripts\python.exe tests/live_health.py`. This uses a synthetic blank image to verify the inference path. For detector, crop, and OCR on the upstream manga example, run `.\.venv\Scripts\python.exe tests/model_smoke.py vendor\comic-text-detector\data\examples\AisazuNihaIrarenai-003.jpg`. Pass that same image path to `tests/live_health.py` to analyze the entire page over HTTP.

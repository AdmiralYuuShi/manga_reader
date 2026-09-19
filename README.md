# Manga Translator

The Windows Flutter app connects to a local FastAPI backend for manga text detection, Japanese OCR, and Indonesian translation.

## Run locally

1. Set up and start the backend using [backend/README.md](backend/README.md).
2. In another PowerShell window, run `flutter run -d windows` from this directory.

The app checks `GET /api/v1/health` on launch. Use the refresh icon after starting the backend. Select a JPEG, PNG, or WebP image with **Open Image**, then select **Analyze Page** to detect regions, run OCR, and translate Japanese to Indonesian. Milestone 4 displays translations over their detected regions. **Translation Overlay** and **Detection Boxes** can be toggled independently without another backend request. Select a region to inspect its Japanese and Indonesian text or a per-region error. Long translations first try progressively expanding the overlay up to 50% beyond the original detector box, within the displayed image and away from neighboring detector boxes. Ellipsis at the minimum font size is the last resort; very small regions remain selectable without overlay text. Detection boxes continue to show the original coordinates. The overlay only covers the original Japanese pixels visually; text removal and inpainting are later work. The backend URL defaults to `http://127.0.0.1:8000`; override it with `flutter run -d windows --dart-define=BACKEND_URL=http://127.0.0.1:9000` if needed. The analysis timeout defaults to 900 seconds and can be set with `--dart-define=ANALYSIS_TIMEOUT_SECONDS=1200`. The default MyMemory translator requires internet access.

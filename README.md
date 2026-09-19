# Manga Translator

The Windows Flutter app connects to a local FastAPI backend for manga text detection, Japanese OCR, and Indonesian translation.

## Run locally

1. Set up and start the backend using [backend/README.md](backend/README.md).
2. In another PowerShell window, run `flutter run -d windows` from this directory.

The app checks `GET /api/v1/health` on launch. Use the refresh icon after starting the backend. Select a JPEG, PNG, or WebP image with **Open Image**, then select **Analyze Page** to detect regions, run OCR, and translate Japanese to Indonesian. Select a box to inspect its Japanese and Indonesian text or a per-region error. The backend URL defaults to `http://127.0.0.1:8000`; override it with `flutter run -d windows --dart-define=BACKEND_URL=http://127.0.0.1:9000` if needed. The analysis timeout defaults to 900 seconds and can be set with `--dart-define=ANALYSIS_TIMEOUT_SECONDS=1200`. Translation requires network access to Google Translate.

# Manga Translator

Milestone 0 establishes a Windows Flutter app connected to a local FastAPI backend.

## Run locally

1. Set up and start the backend using [backend/README.md](backend/README.md).
2. In another PowerShell window, run `flutter run -d windows` from this directory.

The app checks `GET /api/v1/health` on launch and shows **Backend connected** when the server responds. Use **Retry** after starting the backend. The backend URL defaults to `http://127.0.0.1:8000`; override it with `flutter run -d windows --dart-define=BACKEND_URL=http://127.0.0.1:9000` if needed. Detection and OCR are future milestones.

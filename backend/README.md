# Backend setup (Windows PowerShell)

From the `backend` directory:

```powershell
py -3.10 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
python run.py
```

If PowerShell blocks activation, run `.\.venv\Scripts\python.exe -m pip install -r requirements.txt` and `.\.venv\Scripts\python.exe run.py` directly.

The server listens on `http://127.0.0.1:8000` by default. Open `http://127.0.0.1:8000/api/v1/health` to check it. Configure `MANGA_BACKEND_HOST`, `MANGA_BACKEND_PORT`, and `MANGA_LOG_LEVEL` through environment variables. The detector and OCR readiness flags remain `false` until those later milestones are implemented.

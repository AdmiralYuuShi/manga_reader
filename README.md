# Manga Translator

The Windows Flutter app connects to a local FastAPI backend for manga text detection, Japanese OCR, and Indonesian translation.

## Run locally

1. Set up and start the backend using [backend/README.md](backend/README.md).
2. In another PowerShell window, run `flutter run -d windows` from this directory.

## Chapter processing (Milestone 7)

**Open Chapter** selects a folder. Direct child JPEG, PNG, and WebP files are
shown in natural filename order; unrelated files are ignored. **Process Chapter**
sends pending pages one at a time to the existing page analysis endpoint. The
page list shows pending, processing, completed, and failed states. Completed
pages can be inspected immediately with the existing translation overlay,
detection boxes, and region details. Use Previous/Next or the page list to
navigate. **Retry Page** processes only the selected failed page.

**Stop After Page** lets the current HTTP request finish, then leaves later
pages pending. **Process Chapter** resumes those pending pages during the
current session. Opening a new chapter clears the old chapter state. Results
are held in memory and are not restored after an app restart.

The status area shows live page and chapter elapsed time, final durations for
processed pages, and approximate remaining and total time. Estimates initially
show Calculating. After a successful page, they use the last five successful
page durations (or fewer if only fewer exist); failed pages are excluded.
Current page remaining time is clamped to zero when it exceeds the average.
Chapter elapsed time covers each processing run and stops when that run ends.
Milestone 7 was intentionally prioritized before editing (M5) and persistence
(M6) to establish Chapter → Page → Region first.

The app checks `GET /api/v1/health` on launch. Use the refresh icon after starting the backend. Select a JPEG, PNG, or WebP image with **Open Image**, then select **Analyze Page** to detect regions, run OCR, and translate Japanese to Indonesian. Milestone 4 displays translations over their detected regions. **Translation Overlay** and **Detection Boxes** can be toggled independently without another backend request. Select a region to inspect its Japanese and Indonesian text or a per-region error. Long translations first try progressively expanding the overlay up to 50% beyond the original detector box, within the displayed image and away from neighboring detector boxes. Ellipsis at the minimum font size is the last resort; very small regions remain selectable without overlay text. Detection boxes continue to show the original coordinates. The overlay only covers the original Japanese pixels visually; text removal and inpainting are later work. The backend URL defaults to `http://127.0.0.1:8000`; override it with `flutter run -d windows --dart-define=BACKEND_URL=http://127.0.0.1:9000` if needed. The analysis timeout defaults to 900 seconds and can be set with `--dart-define=ANALYSIS_TIMEOUT_SECONDS=1200`. The default MyMemory translator requires internet access.

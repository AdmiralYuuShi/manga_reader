# Manga Translator

The Windows Flutter app connects to a local FastAPI backend for manga text detection, Japanese OCR, and Indonesian translation.

## Run locally

1. Set up and start the backend using [backend/README.md](backend/README.md).
2. In another PowerShell window, run `flutter run -d windows` from this directory.

## Reader workspace (Milestone 12)

The Windows workspace keeps the manga page in the center. In chapter mode, the
left page list shows selection, processing state, cache hits, and edits; the
page arrows remain available when the window is too narrow for that list.
Select a text region to open its source, machine translation, translation
override, and original-pixel geometry in the right inspector. On narrow
windows the inspector moves below the viewer. The bottom strip shows backend,
processing, cache, edit, and error status without covering the page. The
translation and detector-box switches sit above the viewer.

M12 manual validation passed with no issues or regressions. The checklist was:
open one image, analyze it, select a region, edit its translation,
drag and resize its box, then change X/Y/Width/Height numerically and confirm
each change appears on the page. Reopen the image to check saved edits. Open a
chapter, navigate with the left list and page arrows, process pending pages,
and check progress, page status, and page-scoped selection. Resize the window;
check that controls stay usable and boxes stay aligned. View light and dark
application chrome and confirm manga pixels remain unchanged. Restart and
reopen the same image or chapter to check cached results and edits.

## Manga overlay font (Milestone 16)

Open **Settings** in the top action bar to choose one font for all translated
overlays. The selector previews each font. Comic Neue is the default. Selection
updates the current page immediately and is saved automatically in
`overlay_font.json` under Flutter's application-support directory, separate
from chapter metadata and region edits. Missing, invalid, or obsolete IDs fall
back to Comic Neue. All four fonts are bundled, so selection works offline.
The font applies only to translated overlays; app chrome keeps its theme font.
The existing overlay fitter measures the chosen font. Automatic expansion is
visual only and does not change saved text-box geometry.

Font audit (authoritative files from the
[Google Fonts repository](https://github.com/google/fonts); Flutter supports
bundled TTF files through `pubspec.yaml`):

| Candidate | License, available normal weights | M16 decision |
| --- | --- | --- |
| [Comic Neue](https://github.com/google/fonts/tree/main/ofl/comicneue) | SIL OFL 1.1; 300, 400, 700, plus italics | Bundled 400; default |
| [Patrick Hand](https://github.com/google/fonts/tree/main/ofl/patrickhand) | SIL OFL 1.1; 400 | Bundled 400 |
| [Kalam](https://github.com/google/fonts/tree/main/ofl/kalam) | SIL OFL 1.1; 300, 400, 700 | Verified; deferred to keep the selector concise |
| [Schoolbell](https://github.com/google/fonts/tree/main/apache/schoolbell) | Apache 2.0; 400 | Verified; deferred to keep the selector concise |
| [Short Stack](https://github.com/google/fonts/tree/main/ofl/shortstack) | SIL OFL 1.1; 400 | Verified; deferred to keep the selector concise |
| [Coming Soon](https://github.com/google/fonts/tree/main/apache/comingsoon) | Apache 2.0; 400 | Verified; deferred to keep the selector concise |
| [Bangers](https://github.com/google/fonts/tree/main/ofl/bangers) | SIL OFL 1.1; 400 | Bundled 400 |
| [Bowlby One SC](https://github.com/google/fonts/tree/main/ofl/bowlbyonesc) | SIL OFL 1.1; 400 | Verified; deferred to keep the selector concise |
| [Luckiest Guy](https://github.com/google/fonts/tree/main/apache/luckiestguy) | Apache 2.0; 400 | Verified; deferred to keep the selector concise |
| [Permanent Marker](https://github.com/google/fonts/tree/main/apache/permanentmarker) | Apache 2.0; 400 | Bundled 400 |

All candidates have TTF files in that repository. SIL OFL permits bundling
with software when its license and copyright notice travel with the font;
Apache 2.0 likewise permits redistribution with its license and notices.
The exact licenses for bundled files are in `assets/fonts/licenses/`. Bundled
faces use regular weight only. Google Fonts metadata lists Latin coverage for
the selected faces; translations containing other scripts rely on Flutter's
font fallback and may look different within one overlay.

Manual Windows check: launch with no preference and confirm Comic Neue; open
Settings and preview/select several fonts; confirm the visible overlay changes
without OCR or translation rerunning and edited text and geometry remain intact.
Move and resize a selected box, then open another page and chapter/image and
confirm the global font remains selected. Restart, test offline, resize the
window, and confirm the selection persists, the selector does not overflow,
the chrome font stays unchanged, and manga image pixels remain unchanged.

## Appearance (Milestone 17)

**Settings** offers **System**, **Light**, and **Dark** for application chrome.
System is the default and follows Windows appearance changes reported to
Flutter. Selection updates the open reader immediately and is saved alongside
the M16 font ID in `overlay_font.json` under application-support storage.
Existing font-only preferences keep their font and default to System; missing,
unknown, or corrupt appearance values also default to System. Appearance does
not change the selected manga font, chapter metadata, OCR or translation, or
source manga image pixels. Fixed manga overlay and box-handle colors remain for
visibility over artwork. Native Windows title-bar theming is outside M17.

Manual Windows check: start Windows in Light, launch with no appearance
preference, and confirm System uses light chrome. Switch to Dark, Light, and
System; confirm immediate changes to panels, navigation, inspector, controls,
dialogs, and status without any image tint or reprocessing. If practical,
change Windows appearance while System is selected and confirm the app follows.
Open and edit a single image, select and move/resize a region, then switch
themes; confirm text, geometry, selection, and image appearance are intact.
Repeat while navigating a chapter. Change the manga font separately, restart,
and confirm both preferences return. Check the narrow-window reader and
Settings in Light and Dark for overflow and readable contrast; confirm cached
image/chapter data is unchanged.

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
current session. Opening a new chapter clears the current viewer state; valid
saved results are restored when that chapter is opened again.

The compact status strip shows completed-page progress, the current page,
elapsed time, and an approximate remaining time while processing. Page-list
durations show completed runs. Estimates use the last five successful page
durations (or fewer when fewer exist); failed pages are excluded.
Milestone 7 was intentionally prioritized before editing (M5) and persistence
(M6) to establish Chapter → Page → Region first.

## Translation and text-box editing (Milestone 5)

Select a detected region in Open Image or Open Chapter mode to edit its
Indonesian translation. Changes appear in the overlay as you type. The original
machine translation and Japanese OCR text remain visible and unchanged. An
empty translation is a valid edit that hides overlay text; **Reset Translation**
restores the machine result.

The editor also accepts integer X, Y, Width, and Height values in original-image
pixels. **Apply Box** validates positive dimensions and image bounds before
using the box as the translation overlay's base. M4 font fitting and local
expansion still apply to that base. **Detection Boxes** continue to show the
original detector rectangle. **Reset Box** restores the detector geometry
without changing the translation edit. Select a region to show its editable
base-box outline and eight handles. Drag inside the box to move it or drag a
handle to resize it; the numeric fields update live. Geometry stays within the
source image and is saved when the gesture ends. A click alone creates no edit.

Edits belong to their page and region and are saved automatically. Opening a
new image/chapter clears the current viewer state; saved edits return with valid
cached analysis. A successful reanalysis of a page replaces its generated
result and clears that page's earlier edits.

## Persistence and analysis cache (Milestone 6)

Successful page analysis and M5 edits are saved as versioned JSON under the
platform's application-support directory, in `chapters/<SHA-256 of normalized
source folder path>/chapter.json`. **Open Chapter** and **Open Image** use the
same storage. Source manga files remain in place and are never copied or
modified. The JSON stores generated detector/OCR/machine translation separately
from user translation and box overrides. It stores no viewport or font layout.

Each page is matched by its filename relative to the chapter folder and
validated against a SHA-256 hash of its current image bytes. File size and
modification time are recorded as metadata; the hash decides validity. An
unchanged page restores immediately without a backend request. Newly added
pages stay pending, removed pages are absent from the viewer, and a rename is
treated as a new page. Completed pages are saved as they finish. Translation
edits are saved after a 700 ms pause; box changes and resets queue a save
immediately; interactive box gestures save once at completion. Writes are
serialized and use a temporary file plus backup during
replacement.

Changed images, incompatible cache versions, or invalid page data are not
displayed as current results. Their old edits are not applied to new regions;
the old persisted entry remains until a successful reprocess replaces it.
Corrupt or newer-schema chapter files are left untouched, with a warning, and
processing remains available in memory. A save error is shown in the app; work
can continue in memory, but those changes may not survive restart. Valid cached
pages remain viewable even when the backend is unavailable. Historical page
durations can inform ETA, while chapter elapsed time starts fresh each session.

The app checks `GET /api/v1/health` on launch. Use the refresh icon after starting the backend. Select a JPEG, PNG, or WebP image with **Open Image**, then select **Analyze Page** to detect regions, run OCR, and translate Japanese to Indonesian. Milestone 4 displays translations over their detected regions. **Translation Overlay** and **Detection Boxes** can be toggled independently without another backend request. Select a region to inspect its Japanese and Indonesian text or a per-region error. Long translations first try progressively expanding the overlay up to 50% beyond the original detector box, within the displayed image and away from neighboring detector boxes. Ellipsis at the minimum font size is the last resort; very small regions remain selectable without overlay text. Detection boxes continue to show the original coordinates. The overlay only covers the original Japanese pixels visually; text removal and inpainting are later work. The backend URL defaults to `http://127.0.0.1:8000`; override it with `flutter run -d windows --dart-define=BACKEND_URL=http://127.0.0.1:9000` if needed. The analysis timeout defaults to 900 seconds and can be set with `--dart-define=ANALYSIS_TIMEOUT_SECONDS=1200`. The default MyMemory translator requires internet access.

# Manga Translator — Agent Instructions

## 1. Project Overview

This repository contains a **Flutter-based manga translation application**.

The application is intended to:

1. Load manga pages from local images.
2. Detect Japanese text regions automatically.
3. Extract Japanese text using manga-specific OCR.
4. Translate the extracted Japanese text.
5. Display translations as overlays on top of the original manga page.
6. Cache OCR and translation results so pages do not need to be processed repeatedly.
7. Process chapters, preserve analysis and user edits, and support a practical desktop reader/editor in Version 1.
8. Add text removal/inpainting, automatic lettering, and export in Version 2.

The initial implementation should prioritize:

- correctness,
- maintainability,
- modularity,
- local development,
- Windows desktop,
- separation between Flutter UI and ML/OCR processing.

Do not prematurely optimize for Android, iOS, or Web.

The initial platform target is **Windows desktop**.

---

# 2. Core Technology Stack

## Frontend

Use:

- Flutter
- Dart
- Material
- HTTP/REST communication with the local backend

Prefer stable Flutter/Dart APIs and avoid unnecessary dependencies.

## Backend

Use:

- Python 3.10+
- FastAPI
- Uvicorn
- Pydantic
- Pillow
- NumPy
- OpenCV where required

## Text Detection

Use:

https://github.com/dmMaze/comic-text-detector

Purpose:

- detect text regions,
- determine text bounding boxes,
- obtain text masks where available.

Do not use comic-text-detector as the OCR engine.

## OCR

Use:

https://github.com/kha-white/manga-ocr

Purpose:

Japanese manga text recognition.

It should receive cropped text regions produced from the detector output.

## Reference Implementation

Use:

https://github.com/kha-white/mokuro

as an architectural and implementation reference for combining:

comic-text-detector

with:

manga-ocr

Do not copy Mokuro architecture blindly.

This application has different requirements because Flutter is responsible for presentation and interaction while Python acts as the processing backend.

---

# 3. High-Level Architecture

The application follows a client/backend architecture.

```text
┌──────────────────────────────────────┐
│               Flutter                │
│                                      │
│ Manga Reader                         │
│ Image Import                         │
│ Translation Overlay                  │
│ Region Inspector                     │
│ Translation / Geometry Editor        │
│ Settings                             │
└──────────────────┬───────────────────┘
                   │
                   │ REST / JSON
                   │
┌──────────────────▼───────────────────┐
│          Local Python Backend        │
│                                      │
│ FastAPI                              │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ Manga Processing Pipeline        │ │
│ │                                  │ │
│ │ comic-text-detector              │ │
│ │          ↓                       │ │
│ │ text region extraction           │ │
│ │          ↓                       │ │
│ │ manga-ocr                        │ │
│ │          ↓                       │ │
│ │ translation                      │ │
│ └──────────────────────────────────┘ │
└──────────────────────────────────────┘
```

Flutter must not directly depend on Python ML libraries.

Python ML implementation details must not leak into the Flutter domain layer.

---

# 4. Processing Pipeline

The fundamental pipeline is:

```text
Manga Page
    ↓
Image Validation
    ↓
comic-text-detector
    ↓
Detected Text Regions
    ↓
Region Normalization
    ↓
Crop Text Region
    ↓
manga-ocr
    ↓
Japanese Text
    ↓
Translation
    ↓
Structured Page Result
    ↓
Flutter
```

Each processing stage should be independently replaceable.

Do NOT create one large function containing detection, OCR, translation, caching, and serialization.

---

# 5. Text Detection

comic-text-detector is responsible for locating text.

Detector output should be normalized into application-specific domain objects.

Example:

```python
TextRegion(
    id="region_001",
    x=1020,
    y=230,
    width=310,
    height=420,
)
```

The rest of the application should not depend directly on comic-text-detector-specific classes.

Create an abstraction such as:

```python
class TextDetector:
    async def detect(self, image) -> list[DetectedRegion]:
        ...
```

Possible implementation:

```python
class ComicTextDetector(TextDetector):
    ...
```

This allows replacement or experimentation with another detector later.

---

# 6. OCR

OCR should be abstracted similarly.

Example:

```python
class OcrEngine:
    async def recognize(self, image) -> str:
        ...
```

Implementation:

```python
class MangaOcrEngine(OcrEngine):
    ...
```

Do not initialize the manga-ocr model for every request.

The model should be initialized once and reused.

Desired lifecycle:

```text
Backend startup
      ↓
Load manga-ocr
      ↓
Keep model in memory
      ↓
Process multiple requests
```

Avoid:

```text
HTTP request
      ↓
Load model
      ↓
OCR
      ↓
Unload
```

because model initialization is expensive.

---

# 7. Translation

Translation must be independent from OCR.

Define an interface such as:

```python
class Translator:
    async def translate(
        self,
        text: str,
        source_language: str,
        target_language: str,
    ) -> str:
        ...
```

Do not tightly couple the application to a single translation provider.

Possible future implementations may include:

```text
Translator
├── GoogleTranslator
├── DeepLTranslator
├── OpenAITranslator
└── LocalTranslator
```

For the initial OCR-only milestone, a mock or passthrough translator is acceptable.

Example:

```python
class PassthroughTranslator(Translator):
    async def translate(...):
        return text
```

Translation integration should come after the detection + OCR pipeline is reliable.

---

# 8. Backend Folder Structure

Prefer the following structure:

```text
backend/
│
├── app/
│   │
│   ├── main.py
│   │
│   ├── config.py
│   │
│   ├── dependencies.py
│   │
│   ├── api/
│   │   ├── router.py
│   │   └── routes/
│   │       ├── health.py
│   │       └── pages.py
│   │
│   ├── core/
│   │   ├── exceptions.py
│   │   └── logging.py
│   │
│   ├── models/
│   │   ├── page.py
│   │   ├── region.py
│   │   └── translation.py
│   │
│   ├── schemas/
│   │   ├── page.py
│   │   └── region.py
│   │
│   ├── services/
│   │   ├── manga_processor.py
│   │   ├── detection/
│   │   │   ├── base.py
│   │   │   └── comic_text_detector.py
│   │   │
│   │   ├── ocr/
│   │   │   ├── base.py
│   │   │   └── manga_ocr.py
│   │   │
│   │   └── translation/
│   │       ├── base.py
│   │       └── passthrough.py
│   │
│   └── utils/
│       ├── image.py
│       └── geometry.py
│
├── tests/
│   ├── unit/
│   └── integration/
│
├── requirements.txt
└── README.md
```

Avoid unnecessary abstraction beyond this structure.

---

# 9. Flutter Folder Structure

Use a feature-oriented Flutter architecture.

Recommended:

```text
lib/
│
├── app/
│   ├── app.dart
│   └── router.dart
│
├── core/
│   ├── api/
│   │   └── api_client.dart
│   │
│   ├── config/
│   ├── error/
│   ├── extensions/
│   ├── theme/
│   └── utils/
│
├── features/
│   │
│   ├── manga_reader/
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │
│   ├── manga_processing/
│   │   ├── data/
│   │   │   ├── models/
│   │   │   ├── repositories/
│   │   │   └── sources/
│   │   │
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   └── repositories/
│   │   │
│   │   └── presentation/
│   │
│   ├── translation/
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │
│   └── settings/
│       ├── data/
│       ├── domain/
│       └── presentation/
│
└── main.dart
```

Do not create layers or files that contain no meaningful responsibility merely to satisfy the structure.

---

# 10. Flutter Architecture Rules

Use feature-oriented architecture.

Dependencies should generally flow:

```text
presentation
     ↓
domain
     ↓
data
```

UI code should not directly make HTTP requests.

Bad:

```dart
class MangaPage extends StatelessWidget {
  void process() {
    http.post(...);
  }
}
```

Preferred:

```text
Widget
 ↓
State Management
 ↓
Repository
 ↓
Remote Data Source
 ↓
API Client
```

Domain entities must not contain JSON serialization logic.

API models/DTOs handle serialization.

---

# 11. State Management

Do not introduce state-management dependencies without a concrete need.

If a state-management solution is already established in the repository, continue using it consistently.

For asynchronous manga processing, represent at least:

```text
initial
processing
success
failure
```

Processing state may later include progress:

```dart
processing(
  currentPage: 4,
  totalPages: 20,
)
```

Avoid business logic inside widgets.

---

# 12. API Contract

Base development URL:

```text
http://127.0.0.1:8000
```

Version API endpoints.

Base:

```text
/api/v1
```

---

# 13. Health Endpoint

```http
GET /api/v1/health
```

Response:

```json
{
  "status": "ok",
  "detector_ready": true,
  "ocr_ready": true
}
```

Flutter should be able to use this endpoint to determine whether the local backend is available.

---

# 14. Analyze Page Endpoint

Primary endpoint:

```http
POST /api/v1/pages/analyze
```

Content type:

```text
multipart/form-data
```

Fields:

```text
image
target_language
translate
```

Example:

```text
image = page001.jpg
target_language = id
translate = true
```

Do not encode large images as base64 JSON unless required by a future platform.

Use multipart uploads.

---

# 15. Analyze Page Response

Example:

```json
{
  "page": {
    "width": 1600,
    "height": 2400
  },
  "regions": [
    {
      "id": "region_001",
      "bbox": {
        "x": 1020,
        "y": 230,
        "width": 310,
        "height": 420
      },
      "source_language": "ja",
      "source_text": "今日は学校に行くの？",
      "translation": "Hari ini kamu pergi ke sekolah?",
      "confidence": null
    }
  ],
  "processing": {
    "detection_ms": 215,
    "ocr_ms": 840,
    "translation_ms": 120,
    "total_ms": 1175
  }
}
```

Coordinates refer to the ORIGINAL image dimensions.

Never return coordinates based on a resized inference image without converting them back to original image coordinates.

This is critical for Flutter overlays.

---

# 16. Bounding Box Contract

Use:

```json
{
  "x": 100,
  "y": 200,
  "width": 300,
  "height": 400
}
```

Where:

```text
x      = left
y      = top
width  = region width
height = region height
```

Coordinate origin:

```text
(0,0)
 ┌─────────────────────────► X
 │
 │
 │
 ▼
 Y
```

Flutter must scale these coordinates according to the rendered image dimensions.

Do not permanently convert coordinates into percentages in the backend.

Original pixel coordinates are the canonical representation.

---

# 17. Flutter Overlay Calculation

Given:

```text
original image width  = W
original image height = H

displayed width       = Dw
displayed height      = Dh
```

Scale:

```text
scaleX = Dw / W
scaleY = Dh / H
```

Overlay:

```text
displayX      = x * scaleX
displayY      = y * scaleY
displayWidth  = width * scaleX
displayHeight = height * scaleY
```

Take BoxFit behavior into account.

Do not assume the image always fills its widget exactly.

---

# 18. Internal Page Metadata

Processed results are persisted by M6 in versioned JSON under application-support storage.

Recommended representation:

```text
project/
├── images/
│   ├── 001.jpg
│   ├── 002.jpg
│   └── 003.jpg
│
└── metadata/
    ├── 001.json
    ├── 002.json
    └── 003.json
```

Example:

```json
{
  "schema_version": 1,
  "image": "001.jpg",
  "width": 1600,
  "height": 2400,
  "regions": [
    {
      "id": "region_001",
      "bbox": {
        "x": 1020,
        "y": 230,
        "width": 310,
        "height": 420
      },
      "source_text": "今日は学校に行くの？",
      "translated_text": "Hari ini kamu pergi ke sekolah?",
      "ocr_edited": false,
      "translation_edited": false
    }
  ]
}
```

Always include:

```text
schema_version
```

so metadata can evolve without silently breaking older projects.

---

# 19. Model Lifecycle

ML models are expensive resources.

Models should be loaded during application/backend initialization and reused.

Desired lifecycle:

```text
FastAPI startup
      ↓
Initialize detector
      ↓
Initialize OCR
      ↓
Application ready
      ↓
Request
Request
Request
...
```

Do not reload model weights for each region or page.

---

# 20. GPU / Device Selection

The development machine may have NVIDIA CUDA support.

Device selection should preferably support:

```text
auto
cuda
cpu
```

Default:

```text
auto
```

Behavior:

```text
CUDA available
      ↓
use CUDA

otherwise
      ↓
use CPU
```

Do not assume CUDA is always available.

Log which device is selected during backend startup.

---

# 21. Image Handling

Preserve the original image.

Never modify the source file during OCR processing.

Use temporary or in-memory crops.

Pipeline:

```text
original
   ↓
detector inference copy
   ↓
bounding boxes
   ↓
crop from original
   ↓
OCR
```

Detector resizing must not affect the canonical coordinates returned by the API.

---

# 22. Reading Order

Japanese manga may contain:

- vertical text,
- horizontal text,
- right-to-left panel/text ordering.

Do not assume standard Western left-to-right reading order.

Initial MVP may use detector-provided ordering if appropriate.

Reading-order handling should remain isolated so it can be improved later.

Possible future abstraction:

```python
class ReadingOrderResolver:
    def resolve(
        self,
        regions: list[DetectedRegion],
    ) -> list[DetectedRegion]:
        ...
```

Do not embed complex reading-order heuristics inside OCR code.

---

# 23. Error Handling

Backend errors must return structured responses.

Example:

```json
{
  "error": {
    "code": "OCR_FAILED",
    "message": "Unable to recognize text region.",
    "details": null
  }
}
```

Possible error codes:

```text
INVALID_IMAGE
UNSUPPORTED_IMAGE
DETECTION_FAILED
OCR_FAILED
TRANSLATION_FAILED
MODEL_NOT_READY
INTERNAL_ERROR
```

Do not expose Python stack traces through the API.

Log stack traces on the backend.

---

# 24. Partial Failure

One failed OCR region should not necessarily fail the entire page.

For example:

```json
{
  "id": "region_004",
  "source_text": null,
  "translation": null,
  "error": {
    "code": "OCR_FAILED"
  }
}
```

Continue processing other regions where possible.

---

# 25. Logging

Use Python logging.

Do not use scattered `print()` statements for application logging.

Useful startup log:

```text
Starting Manga Translator backend
Device: cuda
Loading comic-text-detector...
comic-text-detector ready
Loading manga-ocr...
manga-ocr ready
Server ready
```

Useful processing log:

```text
Processing page: 001.jpg
Detected regions: 8
OCR completed: 7/8
Detection: 230 ms
OCR: 910 ms
Total: 1.24 s
```

Avoid logging full image data or secrets.

---

# 26. Python Coding Conventions

Follow standard Python conventions.

Use:

- type hints,
- async endpoints where appropriate,
- Pydantic schemas,
- dependency injection where useful,
- descriptive names,
- small focused functions.

Prefer:

```python
async def analyze_page(
    image: UploadFile,
    processor: MangaProcessor,
) -> PageAnalysis:
```

over loosely typed code.

Avoid global mutable application state except deliberately managed model singletons/resources.

---

# 27. Dart / Flutter Coding Conventions

Follow Dart conventions.

Use:

```text
snake_case.dart
```

for filenames.

Use:

```text
PascalCase
```

for classes.

Use:

```text
camelCase
```

for variables/functions.

Prefer immutable models where practical.

Use `const` widgets where possible.

Avoid excessively large widget build methods.

Extract widgets when they represent meaningful UI components, not merely to reduce line count.

---

# 28. Generated Assets

If `flutter_gen_runner` is configured in the project, use generated asset references.

Prefer:

```dart
Assets.images.example.image()
```

or appropriate generated APIs.

Avoid manually repeating asset path strings such as:

```dart
Image.asset('assets/images/example.png')
```

when FlutterGen already exposes the asset.

---

# 29. Networking Conventions

All backend requests should pass through a centralized API client.

Example:

```text
ApiClient
   ↓
MangaProcessingRemoteDataSource
   ↓
MangaProcessingRepository
```

Do not scatter localhost URLs throughout the application.

Backend base URL must be configurable.

Example development value:

```text
http://127.0.0.1:8000
```

---

# 30. Timeouts

ML processing can take significantly longer than ordinary REST requests.

Do not use very short HTTP timeouts.

Processing timeout should be configurable.

Do not silently retry expensive OCR requests unless the operation is known to be safe and idempotent.

---

# 31. Cancellation

Design long-running processing so cancellation can be added later.

Future use case:

```text
Processing chapter

Page 12 / 80

[Cancel]
```

Do not tightly couple processing to UI lifecycle.

---

# 32. Testing Strategy

## Backend Unit Tests

Test independently:

- geometry conversion,
- bounding box normalization,
- metadata serialization,
- image validation,
- translation abstraction,
- processing orchestration.

Mock ML models where possible.

Do not require loading multi-hundred-megabyte models for ordinary unit tests.

## Backend Integration Tests

Integration tests may test:

```text
sample manga page
       ↓
detector
       ↓
OCR
       ↓
expected non-empty regions/text
```

Mark expensive model tests separately.

## Flutter Unit Tests

Test:

- DTO parsing,
- entity mapping,
- repository behavior,
- coordinate calculations.

## Flutter Widget Tests

Test:

- loading state,
- processing state,
- error state,
- translated overlay rendering.

---

# 33. Performance Rules

Do not optimize prematurely.

However, avoid obvious expensive behavior.

Never:

- initialize models for every request,
- reload the same image repeatedly,
- OCR identical regions unnecessarily,
- encode huge images into JSON base64,
- perform expensive image processing on Flutter's UI isolate.

Measure before optimizing.

Useful measurements:

```text
detection_ms
ocr_ms
translation_ms
total_ms
```

---

# 34. Caching

Page analysis results are cached by M6 when the source image hash matches.

A simple cache key may be derived from:

```text
image hash
+
detector version
+
OCR model version
```

Translation cache should additionally consider:

```text
source text
target language
translator/provider
translation configuration
```

Do not implement complex caching before the MVP pipeline works.

---

# 35. Security

The initial backend runs locally.

Bind development backend to:

```text
127.0.0.1
```

unless LAN access is explicitly required.

Do not default to:

```text
0.0.0.0
```

for a desktop-local application.

Never hardcode translation API keys in source code.

Use environment variables or secure configuration.

Do not commit `.env` containing secrets.

---

# 36. Supported Image Formats

Initial support:

```text
.jpg
.jpeg
.png
.webp
```

Validate:

- file type,
- image decoding,
- dimensions,
- reasonable file size.

Do not trust only the file extension.

---

# 37. Chapter Processing

M7 orchestrates chapter pages in Flutter and sends each page sequentially to:

```http
POST /api/v1/pages/analyze
```

No chapter endpoint is needed for the initial implementation. Detector and OCR
instances remain loaded once by the backend lifespan and are reused by these
page requests.

Current workflow:

```text
Folder
 ↓
discover pages
 ↓
sort pages
 ↓
process page 1
 ↓
process page 2
 ↓
...
 ↓
keep results in memory
```

Progress, page status, elapsed time, and approximate ETA are observable from
Flutter. M6 persists successful page analysis and user overrides.

---

# 38. Version 2 Text Removal

comic-text-detector may provide masks useful for text removal.

Future pipeline:

```text
Detected region
      ↓
Text mask
      ↓
Inpainting
      ↓
Clean speech bubble
```

Keep masks available in the backend architecture when practical.

Do not implement inpainting during the initial OCR MVP.

---

# 39. Version 2 Lettering

Eventually translated text may be rendered directly into speech bubbles.

Pipeline:

```text
Original
   ↓
Text Detection
   ↓
OCR
   ↓
Translation
   ↓
Text Removal
   ↓
Font Layout
   ↓
Translated Lettering
   ↓
Export
```

This requires future components for:

- font selection,
- text wrapping,
- vertical alignment,
- font-size fitting,
- bubble boundaries,
- text orientation.

Do not mix these responsibilities into OCR services.

---

# 40. Version 2 Export

Potential export formats:

```text
PNG/JPEG translated pages
ZIP/CBZ
project metadata
```

Export must not destroy original manga images.

---

# 41. MVP UI

The first usable Flutter interface should be simple.

Suggested layout:

```text
┌──────────────────────────────────────────────┐
│ Manga Translator                            │
├──────────────────────────────────────────────┤
│ [Open Image]            Backend: Connected  │
├──────────────────────────────────────────────┤
│                                              │
│                                              │
│                Manga Image                   │
│                                              │
│         ┌───────────────────────┐            │
│         │ translated text       │            │
│         └───────────────────────┘            │
│                                              │
├──────────────────────────────────────────────┤
│ Detected Text                                │
│                                              │
│ 今日は学校に行くの？                         │
│ Hari ini kamu pergi ke sekolah?             │
│                                              │
└──────────────────────────────────────────────┘
```

Prioritize functionality over visual polish during early milestones.

---

# 42. Region Interaction

Eventually clicking an overlay should select its region.

Selected region should expose:

```text
Original Japanese
OCR text
Translated text
Bounding box
Edit controls
```

Manual correction is important because OCR and machine translation will never be perfectly reliable.

Design domain models with editable source and translated text in mind.

---

# 43. Processing Status

Flutter should clearly communicate processing stages.

Examples:

```text
Detecting text...
Recognizing Japanese text...
Translating...
Done
```

Do not freeze the UI while processing.

---

# 44. Dependency Policy

Before adding a dependency:

1. Check whether Flutter/Dart/Python standard functionality already solves the problem.
2. Prefer actively maintained libraries.
3. Avoid dependencies for trivial utilities.
4. Explain significant new dependencies before introducing them.

Do not replace existing project dependencies merely because another library is preferred personally.

---

# 45. Reference Repositories

Important references:

comic-text-detector:

https://github.com/dmMaze/comic-text-detector

manga-ocr:

https://github.com/kha-white/manga-ocr

mokuro:

https://github.com/kha-white/mokuro

When implementation details are uncertain, inspect the current upstream repository rather than assuming its API.

Upstream APIs may change.

---

# 46. Git Rules

Make focused changes.

Avoid unrelated refactoring while implementing a feature.

Do not:

- rename unrelated files,
- reformat the entire repository,
- replace architecture without justification,
- modify generated files manually.

Keep commits/features conceptually focused.

---

# 47. Agent Behavior

Before implementing a task:

1. Inspect relevant existing files.
2. Understand the current architecture.
3. Identify existing patterns.
4. Reuse those patterns where appropriate.
5. Determine the smallest coherent implementation.
6. Implement.
7. Run formatting/static analysis.
8. Run relevant tests.
9. Report what changed.

Do not immediately generate an entirely new architecture if an existing implementation already exists.

---

# 48. Agent Modification Rules

When asked to implement a feature, modify the repository directly when appropriate.

Do not only provide code snippets if the task clearly requests implementation.

Before changing existing code, inspect the full relevant file rather than relying only on a small snippet.

When changing a public interface, search for all usages first.

When deleting code, verify that it is unused.

---

# 49. Validation After Flutter Changes

After meaningful Flutter changes, run as appropriate:

```bash
dart format .
flutter analyze
```

Run relevant tests:

```bash
flutter test
```

Do not claim validation succeeded unless the command actually succeeded.

If a command fails because of environment configuration, report the exact limitation.

---

# 50. Validation After Python Changes

Use formatting/linting/testing tools configured by the repository.

At minimum, ensure changed Python files compile/import correctly.

Run tests when available.

Do not claim the detector or OCR pipeline works unless it was actually executed successfully.

Distinguish:

```text
implemented
```

from:

```text
verified with real model inference
```

---

# 51. Avoid Fabrication

Never invent:

- package APIs,
- model options,
- comic-text-detector outputs,
- manga-ocr configuration,
- benchmark results,
- supported platforms.

If an upstream API is unclear, inspect the upstream repository/documentation first.

---

# 52. Implementation Milestones

Development should proceed incrementally.

## Milestone 0 — Repository Setup

Goal:

Establish project structure.

Tasks:

- Flutter project structure.
- Python backend structure.
- Python virtual environment instructions.
- FastAPI setup.
- configuration system.
- logging.
- `/api/v1/health`.
- Flutter API client.
- backend connectivity indicator.

Definition of done:

```text
Flutter → FastAPI → health response
```

works locally.

---

## Milestone 1 — Text Detection

Goal:

Detect manga text regions.

Tasks:

- integrate comic-text-detector,
- initialize detector once,
- accept manga image upload,
- detect text regions,
- normalize bounding boxes,
- return regions through API,
- render bounding boxes in Flutter.

Expected pipeline:

```text
Flutter
 ↓
Image
 ↓
FastAPI
 ↓
comic-text-detector
 ↓
Bounding boxes
 ↓
Flutter
 ↓
Overlay boxes
```

Definition of done:

A manga page opened in Flutter displays correctly aligned detected text regions.

Do not integrate translation yet.

---

## Milestone 2 — Manga OCR

Goal:

Recognize Japanese text.

Tasks:

- integrate manga-ocr,
- initialize OCR model once,
- crop detected regions,
- OCR each region,
- associate OCR result with region,
- handle per-region OCR failure,
- return Japanese text,
- display text in Flutter.

Expected response:

```text
region
├── bbox
└── source_text
```

Definition of done:

Selecting a detected region in Flutter shows its recognized Japanese text.

---

## Milestone 3 — Translation

Goal:

Translate OCR output.

Tasks:

- define Translator interface,
- implement selected translation provider,
- configure target language,
- translate each recognized region,
- handle translation errors,
- display translation.

Result:

```text
region
├── bbox
├── source_text
└── translated_text
```

Definition of done:

A manga page can be loaded and translated text can be inspected in Flutter.

---

## Milestone 4 — Translation Overlay

Goal:

Display translation directly over manga.

Tasks:

- coordinate scaling,
- responsive overlays,
- region selection,
- show/hide translation,
- distinguish selected region,
- handle zoom/pan.

Definition of done:

Translation remains aligned with the appropriate region during resizing and zooming.

---

## Milestone 5 — Editing

Goal:

Allow non-destructive user overrides for translation text and translation
text-box geometry. Japanese OCR text remains read-only in this scope.

Tasks:

- edit translated text without replacing the machine translation,
- override translation box x/y/width/height in original-image pixels without
  replacing the detector bbox,
- reset translation and geometry independently,
- update the M4 overlay from effective user overrides immediately.

Generated detector/OCR/translator outputs and user edits must remain separate.
Effective translation is the edited text when present (including an intentional
empty string), otherwise the machine translation. Effective base geometry is
the edited box when present, otherwise the detector box. M4 automatic expansion
starts from the effective base box; Detection Boxes show the original detector
box. M6 persists generated data and overrides. M9 should consume effective
text and geometry where appropriate. M5 state is in memory only.

Definition of done:

Users can edit translation and translation placement without reprocessing.

---

## Milestone 6 — Persistence

Goal:

Restore valid generated chapter analysis and non-destructive M5 user overrides
across application restarts without repeating detection, OCR, or translation.

Persistence principles:

- Keep generated detector/OCR/machine translation data distinct from user edits.
- Preserve original generated values and optional M5 overrides separately.
- Validate persisted analysis against each source image before displaying it.
- Never silently show stale analysis or migrate edits to changed image regions.
- Treat user edits more carefully than disposable generated cache.
- Use explicit persistence and analysis-cache schema versions.
- Write metadata atomically where practical and report save failures.
- Load valid results without requiring the Python backend.
- Store metadata in Flutter application-support storage, not source chapters.
- Never modify or duplicate source manga images.

Tasks:

- page metadata schema,
- schema versioning,
- save results,
- load results,
- image hash,
- detect stale processing results.

Definition of done:

Closing and reopening a processed manga does not require OCR again.

---

## Milestone 7 — Chapter Processing

Goal:

Process multiple manga pages.

Tasks:

- folder import,
- page ordering,
- processing queue,
- progress,
- cancellation,
- failure handling,
- in-memory chapter state and timing.

Example:

```text
Processing chapter

████████████░░░░░░

34 / 50 pages

Current:
034.jpg

[Cancel]
```

Definition of done:

A complete chapter can be processed without manually selecting every page.

---

## Milestone 8 — Text Removal / Inpainting

Status: DEFERRED TO VERSION 2. Do not implement during Version 1.

Goal:

Remove original Japanese lettering.

Tasks:

- use detector masks,
- evaluate inpainting options,
- create cleaned page,
- preserve original page.

Do not start this milestone before detection coordinates and masks are reliable.

---

## Milestone 9 — Automatic Lettering

Status: DEFERRED TO VERSION 2. Do not implement during Version 1.

Goal:

Render translated text into cleaned manga bubbles.

Tasks:

- bubble-aware layout,
- font fitting,
- wrapping,
- alignment,
- text orientation,
- rendering.

This is a separate concern from translation.

---

## Milestone 10 — Export

Status: DEFERRED TO VERSION 2. Do not implement during Version 1.

Goal:

Produce shareable translated manga.

Potential formats:

- images,
- ZIP,
- CBZ.

Original files must remain untouched.

---

# 53. Current Priority

Milestone numbers identify feature groups, not chronological implementation order.
M0, M1, M2, M3, M4, M7, M5, and M6 are COMPLETE and have been manually
validated through M6. M6 includes persistent generated analysis and M5
overrides, SHA-256 source validation, cache invalidation, autosave, and cached
Open Chapter/Open Image restoration without backend analysis when valid.

## Version 1 — Practical desktop manga translation reader/editor

Version 1 prioritizes reliable detection/OCR/translation, usable overlays,
manual correction, direct text-box editing, acceptable processing time, a
reader-oriented UI, global font and appearance preferences, recursive chapter
organization, a persistent translated-content library, and reliable cache.
It does not require a cleaned or typeset scanlation image.

Version 1 major feature implementation order:

```text
M0 → M1 → M2 → M3 → M4 → M7 → M5 → M6
   → M11 → M15 → M12 → M16 → M17 → M13 → M14
```

All planned major V1 features are **FEATURE COMPLETE**. M14 manual Windows
validation passed without issues or regressions. M15 Phase A profiling and
Phase B GPU enablement are complete.

Current phase: **V1 Stabilization / Regression Testing — CURRENT**.

```text
V1 Feature Complete
↓
V1 Stabilization / Regression Testing
↓
V1 Release Candidate
↓
V1.0
```

### M11 — Interactive Text Box Move & Resize (COMPLETE)

Add selected-box move and resize handles in the manga viewer. Keep edited
geometry in original-image pixels and within image bounds. Numeric M5 inputs
and direct manipulation must use the same canonical edited box; do not create
a second geometry model. The detector bbox remains immutable. M4 renders from
effective geometry, and M6 persists the same override. Detailed interaction
requirements belong to the dedicated M11 task.

### M15 — Processing Performance Optimization (COMPLETE)

Phase A — Profiling / Baseline / Investigation: **COMPLETE**. See
`backend/PERFORMANCE.md` for the measured CPU baseline, stage definitions,
runtime/device findings, benchmark procedure, and Phase B validation.
The Phase A Codex run did not measure translation; the user later supplied a
CPU translated client median. Profiling does not change analysis or cache
versions.

Phase B — GPU Enablement / Benchmark: **COMPLETE**. The local virtual
environment has torch 2.5.1+cu124 and torchvision 0.20.1+cu124. Manual
validation confirmed CUDA detector inference, manga-ocr on cuda:0, no OOM,
and 8/8 OCR regions on a representative page. Initial GPU backend inference
was about 1.436 s; additional untranslated client requests had a 0.966 s
median. Flutter end-to-end processing is about 15–20 s per page and is
acceptable for V1. See `backend/PERFORMANCE.md` for timing scope and limits.

GPU acceleration is the M15 optimization adopted for V1. Translation and
network optimization, translation concurrency, OCR batching, chapter
parallelism, FP16, quantization, detector resolution reduction, model
unloading/reloading, and further GPU memory optimization are deferred
technical debt, not blockers. Preserve detector/OCR quality and M6 cache
semantics if any are revisited later.

### M12 — Manga Reader UI Refactor (COMPLETE)

Replace the developer-oriented control-heavy layout with a viewer-centered
desktop reader/editor. Aim for left chapter/page navigation, center manga viewer
with M4 overlay and M11 controls, right selected-region inspector with source,
translation and geometry editing, a compact processing/cache/edit status area,
and minimal high-level actions at the top. Prepare extension points for M14
without implementing the library. Establish theme-aware UI foundations for
M17 through `ThemeData`, `ColorScheme`, and `Theme.of(context)` instead of
scattered hard-coded chrome colors. Application themes must not alter manga
image pixels.

The desktop reader now has a compact action bar and status area, chapter page
navigation, a shared single-page/chapter viewer, and a selected-region inspector.
The existing translation overlay, text and geometry edits, direct box handles,
chapter processing, and persisted edits remain available. Automated Flutter
tests, static analysis, and the Windows build pass. The user completed manual
Windows reader validation successfully with no issues or regressions found.

### M16 — Manga Font Selection (COMPLETE)

Offer a curated, global manga/comic overlay font preference, persisted across
restarts. Candidate fonts include Comic Neue (initial recommendation), Patrick
Hand, Kalam, Schoolbell, Short Stack, Coming Soon, Bangers, Bowlby One SC,
Luckiest Guy, and Permanent Marker. Verify availability, licensing, and package
compatibility during M16. Prefer bundled assets for offline use. Do not add
per-region font choice or M9 automatic lettering in M16.

Four verified fonts are bundled with licenses: Comic Neue (default), Patrick
Hand, Bangers, and Permanent Marker. The global selection is stored separately
from chapter metadata in application-support storage, falls back safely to the
default, and updates translated overlays through the existing adaptive layout.
The compact Settings selector previews each font. See `README.md` for the full
ten-candidate audit and manual Windows checklist. Automated Flutter analysis,
tests, and Windows build pass. The user completed M16 manual validation.

### M17 — Light / Dark Mode (COMPLETE)

Support persisted System, Light, and Dark appearance settings; default to
System. Use Flutter theme architecture. Dark mode changes application chrome
only: preserve source image pixels, brightness, contrast, and stored images.
M12 should prepare for this without another major layout rewrite.

The app uses centralized light and dark Material themes with `ThemeMode` set
from a global System/Light/Dark preference. System is the default and follows
platform brightness. Appearance shares M16's application-support preference
file without entering chapter metadata; old font-only preferences remain valid.
The existing Settings dialog changes appearance live. M12 chrome uses semantic
theme colors, while manga image rendering and fixed overlay/handle colors are
unchanged. See `README.md` for the manual Windows checklist. Automated Flutter
analysis, tests, and Windows build pass. The user completed M17 manual
validation successfully.

### M13 — Recursive Folder / Subfolder Processing (COMPLETE)

Extend direct-child chapter import to nested source folders while preserving
meaningful Folder/Manga Root → Chapter/Subfolder → Page → Region hierarchy.
Do not flatten all images into one chapter. Discover folders safely, retain
natural order within each chapter, and keep M6 persistence compatible. Define
detailed hierarchy behavior in the M13 task.

Directories with direct supported images are chapters; directories with only
descendant chapters are groups. Mixed folders retain their own direct-page
chapter plus child chapters. Discovery is link-safe and naturally ordered.
The reader navigates the source tree while `ChapterController` processes only
the selected chapter. M6's absolute-directory chapter identity and schema are
unchanged, preserving old simple-chapter caches and separating duplicate leaf
names. See `README.md` for behavior, limitations, and the manual checklist.
Automated Flutter analysis, tests, and Windows build passed. The user completed
manual Windows validation successfully.

### M14 — Translation Library / Tree View (COMPLETE)

Provide a persistent tree of known manga roots, chapters, folders, and pages,
including cached, partially processed, pending, and edited states where actual
data supports them. Build on M6 persistence, M12 UI structure, and M13 folder
hierarchy.

The library stores normalized source roots and a dated, lightweight hierarchy
and status snapshot in versioned `library_index.json` under application-support
storage. M13 remains authoritative for current files and hierarchy, M6 for
analysis and edits, and AppPreferences for global settings. Opening a chapter
registers its root automatically. Refresh rediscovers that root and verifies
M6 cached pages against source SHA-256 before labeling them Cached or Edited;
new and stale pages are Pending. Containers derive Partial/Edited status from
descendant pages. A missing root stays registered as Unavailable. Removing a
root deletes only its library entry, preserving source files and M6 caches.
Startup loads the saved index and checks root existence without recursive scans,
image decoding, or translation requests. Reader navigation and chapter
processing still use the existing reader and active chapter. See `README.md`
for behavior, limitations, and the Windows manual checklist. Flutter analysis,
all 78 automated tests, and the Windows release build passed. The user completed
M14 manual Windows validation without issues or regressions. M14 was the final
planned major V1 feature.

### V1 Stabilization / Regression Testing (CURRENT)

This phase is not a new major feature milestone. Perform comprehensive
end-to-end testing and regression testing across completed milestones; fix bugs
and edge cases; make small UX/QoL improvements discovered during testing;
clean up error messages and documentation; and verify release builds. Advance
through a V1 Release Candidate before V1.0. Do not start V2 milestones during
stabilization unless the user intentionally ends the V1 stabilization phase.

Preserve these V1 ownership boundaries:

```text
M13 / filesystem   → source hierarchy
M6                 → cached analysis, fingerprints, translations, edits
M14                → persistent library/index/navigation metadata
AppPreferences     → global application preferences
Reader/controllers → live processing/editor state
```

## Version 2 — Image cleanup, lettering, and export

M8 Text Removal/Inpainting, M9 Automatic Lettering, and M10 Export are
DEFERRED TO VERSION 2, not cancelled. Their intended pipeline is:

```text
Original manga → M8 text removal → cleaned image
              → M9 lettering → final render → M10 export
```

M4 translation overlays remain Version 1's presentation mechanism. Do not
implement M8–M10 or add their dependencies during Version 1 unless explicitly
approved. Preserve the architectural notes for them above.

## Architecture to carry forward

Keep Flutter as frontend and Python FastAPI as the processing backend. Reuse
`POST /api/v1/pages/analyze`; detector and OCR models load once and are reused.
Maintain Chapter → Page → Region, per-page failure isolation, original-image
coordinates, immutable detector bbox/OCR text/machine translation, and separate
non-destructive M5 overrides. M6 persists generated analysis separately from
edits and validates source fingerprints. Original manga files remain untouched.
M4 overlays are presentation-only. Valid cached pages must not trigger
unnecessary backend analysis. Prioritize correctness and bounded resources.

---

# 54. First Implementation Objective

The first end-to-end objective is deliberately small:

```text
Flutter
   ↓
Select one manga image
   ↓
POST image to FastAPI
   ↓
comic-text-detector
   ↓
bounding boxes
   ↓
manga-ocr
   ↓
Japanese strings
   ↓
JSON response
   ↓
Flutter
   ↓
Display image + bounding boxes + OCR text
```

Translation should initially be considered a separate stage.

Once this pipeline works reliably, add translation.

---

# 55. Decision-Making Principle

Prefer:

```text
simple
observable
testable
replaceable
```

over:

```text
clever
highly abstract
prematurely optimized
```

The OCR and translation ecosystem will evolve.

Keep boundaries between:

```text
Flutter UI
Detection
OCR
Translation
Persistence
Image Editing
```

clear enough that any individual component can later be replaced without rewriting the entire application.

---

# 56. Instructions for Codex

When receiving a new implementation request:

1. Read this `AGENTS.md`.
2. Inspect the current repository state.
3. Do not assume every milestone described here has already been implemented.
4. Determine which milestone the repository currently satisfies.
5. Inspect existing implementations before creating new ones.
6. Preserve established patterns unless they conflict with this document or there is a concrete technical reason to change them.
7. Implement only the requested scope plus changes strictly necessary to make it work.
8. Do not silently implement later milestones.
9. Verify the implementation with available tooling.
10. Clearly state anything that could not be verified.

If there is ambiguity involving an upstream ML library, inspect its current official repository before implementation.

The primary objective is not to generate the most code.

The primary objective is to build a reliable manga translation pipeline incrementally.

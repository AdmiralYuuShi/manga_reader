# M15: profiling baseline and GPU validation

Phase A added timing only. Phase B enabled CUDA execution using the same model
weights and inference settings. Neither phase changed request order,
translation behavior, or the API response schema. Every actual
`POST /api/v1/pages/analyze` request emits one `[PERF] page` log line. Startup
separately logs detector and OCR load times and selected devices.

## Stage boundaries

`form_parse` starts in the route wrapper before FastAPI reads multipart form
data and ends on entry to the endpoint. `upload_read` measures the UploadFile
read; `decode` includes Pillow validation, load, EXIF transpose, and RGB
conversion. `detection` includes the detector lock, thread offload, PIL to
NumPy/BGR conversion, upstream inference, and normalized boxes.
`crop_prepare` totals original-image crop calls. `ocr_inference` totals all
sequential OCR lock waits and worker calls. `translation` covers the one
sequential batch adapter call, including provider waits and mapping.
`response_prepare` builds Pydantic objects; `response_serialization` is the
subsequent FastAPI response validation and serialization. `unmeasured` is
remaining route/framework overhead and small Python orchestration work.

Stage times use `perf_counter` seconds and are nonoverlapping. Nested provider
request time is a separate detail and must **not** be added to stage totals.
`translation_requests` counts adapter calls to the provider, including Google
retry attempts; it is zero when translation is disabled. OCR and translation
averages use attempted calls. A request that fails early still emits its
available timings and HTTP status. The existing `processing` API fields keep
their previous semantics, including OCR time covering crops and iteration.

The logs do not include page text or image data. The input dimension/byte log
and detector startup input size help compare equivalent benchmark pages.

## Reproduce a benchmark

Use the same local manga page, machine, backend environment, model weights,
provider, and target language before and after a future change. Do not add
copyrighted benchmark pages to Git. From `backend` in PowerShell:

```powershell
$env:HF_HUB_OFFLINE = '1' # if the OCR model is already cached
.\.venv\Scripts\python.exe run.py
```

Wait for both `[PERF] ..._startup` lines and verify `/api/v1/health` has both
models ready. In another PowerShell window, set your existing local image path:

```powershell
$page = 'D:\path\to\your\page.jpg'
curl.exe -s -o NUL -w 'client total: %{time_total}s\n' -F "image=@$page" -F 'translate=false' http://127.0.0.1:8000/api/v1/pages/analyze
curl.exe -s -o NUL -w 'client total: %{time_total}s\n' -F "image=@$page" -F 'translate=false' http://127.0.0.1:8000/api/v1/pages/analyze
curl.exe -s -o NUL -w 'client total: %{time_total}s\n' -F "image=@$page" -F 'translate=false' http://127.0.0.1:8000/api/v1/pages/analyze
curl.exe -s -o NUL -w 'client total: %{time_total}s\n' -F "image=@$page" -F 'translate=true' http://127.0.0.1:8000/api/v1/pages/analyze
curl.exe -s -o NUL -w 'client total: %{time_total}s\n' -F "image=@$page" -F 'translate=true' http://127.0.0.1:8000/api/v1/pages/analyze
curl.exe -s -o NUL -w 'client total: %{time_total}s\n' -F "image=@$page" -F 'translate=true' http://127.0.0.1:8000/api/v1/pages/analyze
```

Treat the first request in each series as cold-ish, and report every run plus
the median of subsequent runs. The `translate=false` series isolates local
detection and OCR. Translation timing varies with the external MyMemory
service; compare repeated runs and note errors/rate limits. The backend logs
measure server time; `curl` adds client/network overhead. These direct API
calls always analyze. Flutter's M6 cache bypasses the API for valid cached
pages, so clear or use uncached pages when measuring the chapter workflow.

## Baseline recorded 2026-09-20

The ignored upstream example
`vendor/comic-text-detector/data/examples/AisazuNihaIrarenai-003.jpg`
(1654 × 1170, 353,831 bytes) was sent twice through the production FastAPI
route using `TestClient`, `translate=false`, with one loaded model pair. This
is a provisional single-page baseline, not a chapter median.

| Run | Server total | Detection | OCR inference | Decode | Crops | Regions |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| First | 83.880 s | 65.839 s | 17.997 s | 0.035 s | 0.002 s | 24 |
| Second | 85.114 s | 66.830 s | 18.266 s | 0.013 s | 0.002 s | 24 |

Client totals were 83.886 s and 85.116 s. The second run is the sole warm
sample, so its 85.114 s value is **not** a robust warm median. Detection was
78.5% and OCR inference 21.5% of both runs, to rounding. Other stages were
below 0.1% combined. All 24 OCR attempts succeeded, averaging 0.750 s and
0.761 s per region. No translation requests ran in this Codex session because
external network access was unavailable. The user later supplied a CPU
translated client median, recorded in the Phase B comparison below.

The installed environment is Python 3.10.6, PyTorch `2.5.1+cpu`, CUDA runtime
`None`, `torch.cuda.is_available() == False`, manga-ocr 0.1.16, and
deep-translator 1.11.4. The detector selected CPU with 1024 × 1024 upstream
input; manga-ocr selected CPU. Startup measured 6.123 s detector and 4.335 s
OCR. Manga-ocr's constructor includes a sample inference warmup. Those startup
durations are excluded from page totals. An earlier online startup attempt
could not reach Hugging Face; the successful run used cached weights with
`HF_HUB_OFFLINE=1`.

## Phase A architecture and original investigation

FastAPI parses multipart form data, then reads and decodes one image. The
detector adapter converts RGB PIL to NumPy/BGR and calls the upstream model
once at 1024 × 1024. The upstream detector call is under `torch.no_grad()`;
its output is mapped to original-image coordinates. The processor crops each
region from the original image, invokes manga-ocr sequentially in a worker
thread, and then invokes one translation batch adapter in a worker thread.
The MyMemory adapter creates one deep-translator instance per batch and makes
one sequential `requests.get` call per nonempty text, without an explicit
timeout or reusable `Session`. Google remains supported and issues sequential
calls with spacing and rate-limit retries. Duplicate OCR strings are counted
but not deduplicated. The existing chapter controller sends pages sequentially;
its stopwatch includes image read/hash, HTTP transfer, full backend request,
response handling, and source fingerprinting. Its ETA uses the last five
successful page durations. Backend stage timings explain portions of that
larger client duration; improved backend latency should improve future ETA.

The following was the Phase A opportunity matrix before GPU validation:

| Candidate for later phase | Stage | Potential impact | Complexity | Risk / quality / VRAM |
| --- | --- | --- | --- | --- |
| Evaluate a compatible CUDA PyTorch build and detector/OCR device placement | Detection, OCR | High on suitable GPU | Medium | Driver/build compatibility; VRAM must be measured; quality should stay equal |
| Profile detector internals and RGB/BGR copies | Detection | Unknown | Medium | Low quality risk; likely modest versus measured inference time |
| Test lower detector resolution against fixed pages | Detection | Potentially high | Medium | Detection recall may fall; compare boxes/OCR; VRAM may fall |
| Explore OCR preprocessing and safe batching | OCR | Medium | High | Ordering/output changes possible; VRAM may rise |
| Measure provider latency, then consider exact-text cache or bounded requests | Translation | Unknown until translated baseline | Medium | Cache invalidation, rate limits, provider quality; little VRAM |
| Controlled page-stage overlap | Chapter throughput | Unknown | High | Shared model locks, CPU/GPU contention, memory and provider limits |

The original Phase A recommendation was to collect translated and warm
page measurements on representative user pages; then test compatible GPU
availability and measure VRAM without changing inference quality; profile the
detector's internal stages if it remains dominant; evaluate resolution only
with box/OCR quality comparisons; investigate OCR batching and translation
after their measured contributions justify it. Any chapter overlap should be
bounded and designed around shared model ownership and provider limits.

## M15 Phase B: GPU enablement and manual validation (2026-09-20)

**COMPLETE.** GPU acceleration of the existing detector and OCR models is the
primary optimization adopted in M15. The development machine has an NVIDIA
GeForce RTX 3050 Laptop GPU with 4096 MiB VRAM. The earlier hardware audit
reported driver 595.79, CUDA driver compatibility 13.2, and compute capability
8.6. The user subsequently installed torch `2.5.1+cu124` and torchvision
`0.20.1+cu124`; the current virtual environment confirms both versions,
CUDA runtime 12.4, and `torch.cuda.is_available() == True`.

The user manually verified manga-ocr's "Using CUDA" log and actual device
`cuda:0`. Detector CUDA inference was confirmed through GPU allocator
profiling. Both models loaded without CUDA out-of-memory errors. The
`models_loaded` snapshot reported approximately 522.4 MiB allocated and
610.0 MiB reserved; observed inference reservation was approximately
1070 MiB. These are PyTorch allocator figures, not total system VRAM.

The [official PyTorch 2.5.1 installation page](https://docs.pytorch.org/get-started/previous-versions/)
provides matching Windows CUDA 12.4 wheels for torch 2.5.1 and torchvision
0.20.1. The [NVIDIA CUDA 12.4 release notes](https://docs.nvidia.com/cuda/archive/12.4.0/cuda-toolkit-release-notes/)
list Windows driver 551.61 as the minimum; this machine's driver is newer.
PyTorch's wheel supplies the required CUDA runtime; a separate CUDA Toolkit
is not needed for these prebuilt binaries. The repository's torch `<2.6` and
torchvision `<0.21` constraints admit this exact pair without changing
transformers, manga-ocr, or other dependencies.

An earlier Codex attempt could not reach the official wheel host; the user
completed the installation locally. To reproduce it in another prepared
backend virtual environment, run from `backend` in PowerShell:

```powershell
.\.venv\Scripts\python.exe -m pip install --no-deps 'torch==2.5.1+cu124' 'torchvision==0.20.1+cu124' --index-url https://download.pytorch.org/whl/cu124
.\.venv\Scripts\python.exe -c "import torch, torchvision; print(torch.__version__, torchvision.__version__, torch.version.cuda, torch.cuda.is_available(), torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'none')"
```

Do not proceed if imports fail or CUDA remains unavailable. The backend now
accepts `MANGA_DEVICE=auto` (default, CUDA if available), `cpu`, or `cuda`.
An explicit CUDA request fails at startup if PyTorch cannot use CUDA. Detector
and OCR placement are checked after model construction. The detector still
uses the same checkpoint, 1024 × 1024 input, thresholds, preprocessing, and
postprocessing; OCR remains sequential on the same model and crops. Startup
logs PyTorch/CUDA details, selected devices, and PyTorch allocated/reserved
memory before and after model loading. With `MANGA_GPU_PROFILE=1`, page logs
synchronize CUDA at the start/end of detection and OCR measurements and report
each stage's peak PyTorch allocator memory. Keep this flag off for ordinary
processing to avoid extra per-region synchronization. Those numbers are not
the same as total driver VRAM; compare with `nvidia-smi` when repeating a
benchmark. No standalone CUDA Toolkit was required for the wheel installation.

### Recorded GPU results

The user's representative page was 640 x 919 pixels and produced 8 detected
regions with successful OCR in all 8. The initial GPU request measured about
0.589 s detection, 0.775 s OCR inference, 1.436 s backend total, and
1.460 s client total. A further `translate=false` client series measured
1.442330 s, 0.966024 s, and 0.902387 s (series median 0.966024 s). The
first request was slower than later requests; the two later client times have
a median of 0.934206 s. No detailed backend stage logs for those three
additional requests were supplied, so only the initial request has a recorded
stage breakdown.

| Scope | CPU baseline | GPU observation | Interpretation |
| --- | ---: | ---: | --- |
| Representative page, `translate=false`, client median | 59.395279 s | 0.966024 s | About 61.5x lower client latency if the earlier CPU and GPU runs used the same page and request settings |
| Representative page, `translate=true`, client median | 83.201488 s | No comparable API series | No translated-request speedup can be calculated |
| Initial GPU backend, `translate=false` | No matching per-stage CPU record for this page | 1.436 s total; 0.589 s detection; 0.775 s OCR | 41.0% detection, 54.0% OCR, about 5.0% other stages |

The CPU medians above came from the user's earlier manual representative-page
benchmark, not from the upstream example in Phase A. The reported GPU page
dimensions and region count were not recorded alongside that earlier CPU
series, so the 61.5x figure is indicative rather than a controlled
same-file verification. Do not compare the 24-region upstream example's CPU
stage times directly with this 8-region GPU page.

In the user's Flutter workflow, complete processing currently takes about
**15-20 s per page**. That end-to-end observation is separate from the
**approximately 1 s backend/client `translate=false`** benchmark. It can
include translation network latency and other workflow work; no matching
translated backend stage breakdown was supplied, so the remaining time cannot
be assigned to a specific stage. The user found this end-to-end time acceptable
for V1 and observed no CUDA OOM or functional regression. A detailed
CPU-versus-GPU box/OCR output diff and a GPU run of the upstream example were
not supplied; this document does not claim numerical equivalence for them.

### Repeat the GPU benchmark if needed

Use the same representative page as the recorded CPU baseline, without
copying it into this repository:

```powershell
$env:HF_HUB_OFFLINE = '1' # only if manga-ocr weights are cached
$env:MANGA_DEVICE = 'cuda'
$env:MANGA_GPU_PROFILE = '1'
.\.venv\Scripts\python.exe run.py
```

Confirm health reports both models ready and startup logs prove both actual
devices are CUDA. Record `nvidia-smi` before loading, after loading, and while
each stage runs. In a second PowerShell window, use the [benchmark commands
above](#reproduce-a-benchmark) with
`C:\Users\Hapid\Downloads\manga-raw-chapter-101-v0-ukksbvmm1bx81.webp`:
run `translate=false` at least three times and `translate=true` three times
only when MyMemory is reachable. Record every backend `[PERF]` line, first
versus warm runs, warm median, GPU allocator peaks, and `nvidia-smi` usage.
Also run the ignored upstream example with `translate=false` if practical.

For a direct CPU/GPU output comparison, restart the same CUDA-wheel backend
with `MANGA_DEVICE=cpu` and save one response JSON for the same image, then
restart with `MANGA_DEVICE=cuda` and save its response JSON. Compare region
count, ordered `bbox` values, and `source_text`; inspect meaningful box or OCR
differences rather than changing thresholds. Use `translate=false` for this
comparison so provider variability cannot obscure model differences. Compare
GPU timings against a CPU baseline only for the same page and mode. These
repeatability checks are optional follow-up diagnostics, not V1 blockers.

### M15 closeout and deferred work

The GPU-enabled local inference path met the current V1 performance goal
without model-quality setting changes. The initial GPU backend breakdown has
OCR as the largest measured stage (54.0%), followed by detection (41.0%).
The larger 15-20 s Flutter total has no translated backend stage breakdown,
so its primary remaining cost is not established. No further performance
optimization is required for M15 completion.

Translation/network optimization, translation concurrency, OCR batching,
chapter parallelism, FP16, quantization, detector resolution reduction,
model unloading/reloading, and further GPU memory tuning are deferred
technical debt. Revisit them only if a future measured workload requires it,
with separate quality, rate-limit, memory, and correctness checks.

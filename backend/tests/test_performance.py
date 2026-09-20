import asyncio

from PIL import Image

from app.services.detection.base import DetectedRegion
from app.services.manga_processor import MangaProcessor
from app.services.performance import PerformanceMetrics
from app.services.translation.base import TranslationItem


class Detector:
    def detect(self, image):
        return [DetectedRegion(0, 0, 5, 5), DetectedRegion(5, 0, 5, 5)]


class Ocr:
    def __init__(self):
        self.calls = 0

    def recognize(self, image):
        self.calls += 1
        if self.calls == 2:
            raise RuntimeError("expected test failure")
        return "same text"


class Translator:
    def __init__(self):
        self.calls = 0

    def translate_batch(self, texts, source, target):
        self.calls += 1
        return [TranslationItem(translated_text="translated") for _ in texts]


def test_stage_timer_records_failed_stage():
    metrics = PerformanceMetrics()
    try:
        with metrics.stage("failed"):
            raise ValueError("test")
    except ValueError:
        pass
    assert metrics.stages["failed"] >= 0
    assert "failed=" in metrics.summary(1.0, 500)


def test_cuda_stage_synchronizes_and_records_allocator_peak(monkeypatch):
    import torch

    calls = []
    monkeypatch.setattr(torch.cuda, "synchronize", lambda: calls.append("sync"))
    monkeypatch.setattr(torch.cuda, "reset_peak_memory_stats", lambda: calls.append("reset"))
    monkeypatch.setattr(torch.cuda, "max_memory_allocated", lambda: 8 * 1048576)
    monkeypatch.setattr(torch.cuda, "max_memory_reserved", lambda: 12 * 1048576)
    metrics = PerformanceMetrics(gpu_profile=True)
    with metrics.stage("detection", "cuda"):
        pass
    assert calls == ["sync", "reset", "sync"]
    assert metrics.gpu_peaks_mb == {
        "detection_allocated": 8.0, "detection_reserved": 12.0,
    }


def test_pipeline_counts_and_disabled_translation_do_not_change_results():
    async def run(translate):
        translator = Translator()
        metrics = PerformanceMetrics()
        processor = MangaProcessor(Detector(), Ocr(), asyncio.Lock(), asyncio.Lock(), translator)
        result = await processor.process(Image.new("RGB", (10, 5)), translate=translate,
                                         metrics=metrics)
        return result, metrics, translator

    enabled, measured, translator = asyncio.run(run(True))
    disabled, skipped, unused = asyncio.run(run(False))
    assert [r.source_text for r in enabled.regions] == [r.source_text for r in disabled.regions]
    assert enabled.regions[0].translated_text == "translated"
    assert {name: measured.counts[name] for name in (
        "regions", "ocr_attempted", "ocr_succeeded", "ocr_failed",
        "translation_candidates", "translation_skipped", "duplicate_source_texts",
        "translation_requests", "translation_failed",
    )} == {
        "regions": 2, "ocr_attempted": 2, "ocr_succeeded": 1,
        "ocr_failed": 1, "translation_candidates": 1,
        "translation_skipped": 1, "duplicate_source_texts": 0,
        "translation_requests": 0, "translation_failed": 0,
    }
    assert all(stage in measured.stages for stage in
               ("detection", "crop_prepare", "ocr_inference", "translation"))
    assert translator.calls == 1
    assert skipped.provider == "disabled"
    assert skipped.counts["translation_skipped"] == 2
    assert "translation" not in skipped.stages
    assert unused.calls == 0

"""Lightweight per-request timings for local pipeline diagnosis."""

from contextlib import contextmanager
from contextvars import ContextVar
from dataclasses import dataclass, field
import os
from time import perf_counter
from typing import Iterator


current_metrics: ContextVar["PerformanceMetrics | None"] = ContextVar("current_metrics", default=None)


@dataclass
class PerformanceMetrics:
    started: float = field(default_factory=perf_counter)
    stages: dict[str, float] = field(default_factory=dict)
    counts: dict[str, int] = field(default_factory=dict)
    details: dict[str, float] = field(default_factory=dict)
    gpu_peaks_mb: dict[str, float] = field(default_factory=dict)
    provider: str = "unknown"
    gpu_profile: bool = field(default_factory=lambda: os.getenv("MANGA_GPU_PROFILE") == "1")

    @contextmanager
    def stage(self, name: str, device: str = "cpu") -> Iterator[None]:
        cuda = self.gpu_profile and device.startswith("cuda")
        if cuda:
            import torch

            torch.cuda.synchronize()
            torch.cuda.reset_peak_memory_stats()
        start = perf_counter()
        try:
            yield
        finally:
            if cuda:
                torch.cuda.synchronize()
                self.gpu_peaks_mb[f"{name}_allocated"] = max(
                    self.gpu_peaks_mb.get(f"{name}_allocated", 0.0),
                    torch.cuda.max_memory_allocated() / 1048576,
                )
                self.gpu_peaks_mb[f"{name}_reserved"] = max(
                    self.gpu_peaks_mb.get(f"{name}_reserved", 0.0),
                    torch.cuda.max_memory_reserved() / 1048576,
                )
            self.stages[name] = self.stages.get(name, 0.0) + perf_counter() - start

    def count(self, name: str, amount: int = 1) -> None:
        self.counts[name] = self.counts.get(name, 0) + amount

    def add_detail(self, name: str, seconds: float) -> None:
        self.details[name] = self.details.get(name, 0.0) + seconds

    def summary(self, total: float, status: int) -> str:
        measured = sum(self.stages.values())
        stage_text = " ".join(f"{name}={seconds:.3f}s" for name, seconds in self.stages.items())
        count_text = " ".join(f"{name}={value}" for name, value in self.counts.items())
        detail_text = " ".join(f"{name}={seconds:.3f}s" for name, seconds in self.details.items())
        gpu_text = " ".join(f"{name}={value:.1f}MiB" for name, value in self.gpu_peaks_mb.items())
        ocr_average = self.stages.get("ocr_inference", 0.0) / max(1, self.counts.get("ocr_attempted", 0))
        request_average = self.details.get("provider_request_time", 0.0) / max(1, self.counts.get("translation_requests", 0))
        return (
            f"[PERF] page status={status} total={total:.3f}s {stage_text} "
            f"unmeasured={max(0.0, total - measured):.3f}s "
            f"provider={self.provider} {count_text} {detail_text} {gpu_text} "
            f"ocr_avg={ocr_average:.3f}s request_avg={request_average:.3f}s"
        )

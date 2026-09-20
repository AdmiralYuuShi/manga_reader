"""Backend device choice shared by detector and OCR."""


def resolve_device(requested: str, cuda_available: bool) -> str:
    if requested not in {"auto", "cpu", "cuda"}:
        raise ValueError(f"Invalid MANGA_DEVICE '{requested}'; use auto, cpu, or cuda")
    if requested == "cuda" and not cuda_available:
        raise RuntimeError("MANGA_DEVICE=cuda requested but PyTorch CUDA is unavailable")
    return "cuda" if requested == "cuda" or (requested == "auto" and cuda_available) else "cpu"

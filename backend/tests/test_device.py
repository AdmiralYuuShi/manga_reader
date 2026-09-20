import pytest

from app.services.device import resolve_device


@pytest.mark.parametrize("requested,available,expected", [
    ("auto", False, "cpu"), ("auto", True, "cuda"),
    ("cpu", False, "cpu"), ("cpu", True, "cpu"),
    ("cuda", True, "cuda"),
])
def test_device_selection(requested, available, expected):
    assert resolve_device(requested, available) == expected


def test_unavailable_cuda_and_invalid_choice_fail_clearly():
    with pytest.raises(RuntimeError, match="unavailable"):
        resolve_device("cuda", False)
    with pytest.raises(ValueError, match="Invalid MANGA_DEVICE"):
        resolve_device("gpu", True)

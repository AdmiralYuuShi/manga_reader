from fastapi import APIRouter, Request
from pydantic import BaseModel

router = APIRouter()


class HealthResponse(BaseModel):
    status: str
    detector_ready: bool
    ocr_ready: bool


@router.get("/health", response_model=HealthResponse)
def health(request: Request) -> HealthResponse:
    return HealthResponse(
        status="ok", detector_ready=getattr(request.app.state, "detector", None) is not None,
        ocr_ready=False,
    )

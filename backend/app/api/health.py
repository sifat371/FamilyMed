from fastapi import APIRouter, HTTPException, status

from app.db import database_is_ready

router = APIRouter(tags=["health"])


@router.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "service": "familymed-api"}


@router.get("/ready")
async def ready() -> dict[str, str]:
    if not await database_is_ready():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="database unavailable",
        )
    return {"status": "ready"}

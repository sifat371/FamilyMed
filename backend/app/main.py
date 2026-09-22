from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.health import router as health_router
from app.auth.router import router as auth_router
from app.common.errors import ApiError
from app.config import get_settings
from app.doses.router import router as dose_router
from app.families.router import router as family_router
from app.medications.router import router as medication_router
from app.notifications.router import router as notification_router
from app.schedules.router import router as schedule_router

settings = get_settings()

app = FastAPI(title="FamilyMed API", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(ApiError)
async def api_error_handler(_request: Request, exc: ApiError) -> JSONResponse:
    return JSONResponse(status_code=exc.status_code, content=exc.payload())


@app.exception_handler(RequestValidationError)
async def validation_error_handler(_request: Request, exc: RequestValidationError) -> JSONResponse:
    fields = [
        {
            "loc": list(error["loc"]),
            "msg": error["msg"],
            "type": error["type"],
        }
        for error in exc.errors()
    ]
    return JSONResponse(
        status_code=422,
        content={
            "error": {
                "code": "VALIDATION_ERROR",
                "message": "Request validation failed.",
                "details": {"fields": fields},
            }
        },
    )


app.include_router(health_router, prefix="/api/v1")
app.include_router(auth_router, prefix="/api/v1")
app.include_router(family_router, prefix="/api/v1")
app.include_router(medication_router, prefix="/api/v1")
app.include_router(schedule_router, prefix="/api/v1")
app.include_router(dose_router, prefix="/api/v1")
app.include_router(notification_router, prefix="/api/v1")

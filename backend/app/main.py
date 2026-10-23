import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Query, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from . import errors
from .config import settings
from .etus import parsers
from .etus.portal import PortalClient, PortalResult
from .models import (
    ErrorResponse,
    Health,
    LoginRequest,
    MethodResponse,
    ScheduleKind,
    ScheduleList,
    Snapshot,
    Timetable,
)
from .ratelimit import SlidingWindowLimiter
from .schedules import ScheduleService, utc_now_iso
from .timetables import TimetableService

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
logger = logging.getLogger("uniapp")

portal = PortalClient(settings)
schedules = ScheduleService(settings)
timetables = TimetableService(settings, schedules)
ip_limiter = SlidingWindowLimiter(settings.login_limit_per_ip, settings.login_limit_window)
student_limiter = SlidingWindowLimiter(settings.login_limit_per_student, settings.login_limit_window)
method_limiter = SlidingWindowLimiter(settings.login_limit_per_ip * 5, settings.login_limit_window)


@asynccontextmanager
async def lifespan(_: FastAPI):
    schedules.refresh_in_background()
    try:
        portal.solver.warm_up()
    except Exception as error:
        logger.warning("CAPTCHA engine warm-up failed: %s", error)
    yield


app = FastAPI(title="UniApp API", version=settings.version, lifespan=lifespan)

ERROR_RESPONSES = {status: {"model": ErrorResponse} for status in (401, 404, 422, 423, 429, 502, 503)}


def error_payload(code: str, message: str) -> dict:
    return {"error": {"code": code, "message": message}}


@app.exception_handler(errors.ServiceError)
async def service_error_handler(_: Request, error: errors.ServiceError) -> JSONResponse:
    return JSONResponse(status_code=error.status, content=error_payload(error.code, error.message))


@app.exception_handler(RequestValidationError)
async def validation_error_handler(_: Request, error: RequestValidationError) -> JSONResponse:
    return JSONResponse(status_code=422, content=error_payload("validation_error", "Invalid request"))


def client_ip(request: Request) -> str:
    return request.client.host if request.client else "unknown"


def guard_login(request: Request, faculty_no: str) -> None:
    if not ip_limiter.allow(client_ip(request)) or not student_limiter.allow(faculty_no):
        raise errors.rate_limited()


def snapshot_from(result: PortalResult, faculty_no: str) -> Snapshot:
    return Snapshot(
        student=parsers.build_student(result.name, faculty_no, result.info),
        grades=parsers.build_grades(result.semesters),
        dormitory=result.dormitory,
        login_method=result.method,
        fetched_at=utc_now_iso(),
    )


@app.get("/health", response_model=Health)
def health() -> Health:
    return Health(status="ok", version=settings.version, schedules_updated_at=schedules.updated_at)


@app.get("/v2/auth/method", response_model=MethodResponse, responses=ERROR_RESPONSES)
def auth_method(request: Request, faculty_no: str = Query(alias="facultyNo", pattern=r"^\d{3,16}$")) -> MethodResponse:
    if not method_limiter.allow(client_ip(request)):
        raise errors.rate_limited()
    return MethodResponse(method=portal.detect_method(faculty_no))


@app.post("/v2/auth/login", response_model=Snapshot, responses=ERROR_RESPONSES)
def login(request: Request, body: LoginRequest) -> Snapshot:
    guard_login(request, body.faculty_no)
    result = portal.fetch(body.faculty_no, body.secret)
    return snapshot_from(result, body.faculty_no)


@app.get("/v2/schedules", response_model=ScheduleList, responses=ERROR_RESPONSES)
def schedule_list(kind: ScheduleKind = "lectures") -> ScheduleList:
    return schedules.get(kind)


@app.get("/v2/timetables/{schedule_id}", response_model=Timetable, responses=ERROR_RESPONSES)
def timetable(schedule_id: int) -> Timetable:
    return timetables.get(schedule_id)


class LegacyLogin(BaseModel):
    faculty_no: str = Field(min_length=3, max_length=16, pattern=r"^\d+$")
    auth_code: str = Field(min_length=1, max_length=128)


@app.post("/api/login", include_in_schema=False)
def legacy_login(request: Request, body: LegacyLogin) -> dict:
    try:
        guard_login(request, body.faculty_no)
        result = portal.fetch(body.faculty_no, body.auth_code)
    except errors.ServiceError as error:
        return {"status": "error", "message": error.message}
    return {
        "status": "success",
        "name": result.name,
        "info": result.info,
        "grades": parsers.legacy_grade_rows(result.semesters),
        "dormitory": {"status": result.dormitory.status or "Нет данных"},
    }


@app.get("/api/schedules", include_in_schema=False)
def legacy_schedules() -> list[dict]:
    return [
        {
            "faculty": item.faculty,
            "speciality": item.major,
            "course": str(item.year or ""),
            "stream": item.stream or "",
            "url": item.url,
        }
        for item in schedules.get("lectures").items
    ]

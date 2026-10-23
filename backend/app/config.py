import os
from dataclasses import dataclass, field


def _int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, default))
    except ValueError:
        return default


@dataclass(frozen=True)
class Settings:
    version: str = "2.0.0"
    portal_url: str = "https://e-university.tu-sofia.bg/ETUS/studenti/"
    schedules_api: str = "https://tu-sofia.bg/api/schedules"
    request_timeout: float = float(os.getenv("UNIAPP_TIMEOUT", "30"))
    login_attempts: int = _int("UNIAPP_LOGIN_ATTEMPTS", 5)
    captcha_reads: int = _int("UNIAPP_CAPTCHA_READS", 4)
    schedule_ttl: int = _int("UNIAPP_SCHEDULE_TTL", 3 * 60 * 60)
    schedule_page_limit: int = _int("UNIAPP_SCHEDULE_PAGE_LIMIT", 60)
    data_dir: str = os.getenv("UNIAPP_DATA_DIR", "/data")
    login_limit_per_ip: int = _int("UNIAPP_LOGIN_LIMIT_IP", 12)
    login_limit_per_student: int = _int("UNIAPP_LOGIN_LIMIT_STUDENT", 6)
    login_limit_window: int = _int("UNIAPP_LOGIN_LIMIT_WINDOW", 10 * 60)
    user_agent: str = (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
    )
    degrees: tuple[str, ...] = field(default=("bachelor", "master"))
    week_one: str = os.getenv("UNIAPP_WEEK_ONE", "2026-09-14")
    timetable_max_bytes: int = _int("UNIAPP_TIMETABLE_MAX_BYTES", 15 * 1024 * 1024)


settings = Settings()

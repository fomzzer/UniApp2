import json
import logging
import os
import threading
import time
from datetime import datetime, timezone

import httpx

from .config import Settings
from .models import ScheduleItem, ScheduleKind, ScheduleList

logger = logging.getLogger("uniapp.schedules")

KINDS: tuple[ScheduleKind, ...] = ("lectures", "exams")
PAGE_SIZE = 100
FACULTY_SLUGS = (
    "faculty-of-automation",
    "faculty-of-electrical-engineering",
    "faculty-of-power-engineering",
    "faculty-of-industrial-technology",
    "faculty-of-mechanical-engineering",
    "faculty-of-electronic-engineering-and-technologies",
    "faculty-of-telecommunications",
    "faculty-of-computer-systems-and-technologies",
    "faculty-of-transport",
    "faculty-of-economics",
    "faculty-of-applied-mathematics-and-informatics",
    "faculty-of-german-engineering-education-and-industrial-management",
    "faculty-of-french-engineering-education",
    "faculty-of-english-engineering-education",
    "faculty-of-engineering-and-pedagogy-sliven",
    "faculty-of-electronics-and-automation",
    "technical-college-sofia",
    "faculty-of-mechanical-engineering-and-instrumentation",
    "college-sliven",
    "department-of-foreign-language-teaching-and-applied-linguistics",
    "department-of-physical-education-and-sports",
    "department-of-teacher-qualification-and-professional-development",
)


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def normalize(raw: dict, kind: ScheduleKind) -> ScheduleItem | None:
    file_path = raw.get("file_path")
    external = raw.get("external_url")
    url = file_path or external
    faculty = raw.get("faculty") or {}
    major = raw.get("major") or {}
    if not url or not faculty.get("slug") or not major.get("slug"):
        return None
    stream = raw.get("stream")
    year = raw.get("year")
    return ScheduleItem(
        id=int(raw.get("id") or 0),
        kind=kind,
        academic_year=raw.get("academic_year"),
        semester=raw.get("semester"),
        degree=str(raw.get("degree_type") or "bachelor"),
        faculty=str(faculty.get("title") or faculty.get("slug")).strip(),
        faculty_slug=str(faculty.get("slug")),
        major=str(major.get("title") or major.get("slug")).strip(),
        major_slug=str(major.get("slug")),
        year=int(year) if isinstance(year, (int, float)) or (isinstance(year, str) and year.isdigit()) else None,
        stream=str(stream).strip() if stream not in (None, "") else None,
        url=str(url),
        is_pdf=bool(file_path) and str(file_path).lower().split("?")[0].endswith(".pdf"),
    )


def sort_key(item: ScheduleItem) -> tuple:
    stream = item.stream or ""
    stream_number = int(stream) if stream.isdigit() else 999
    return (item.degree, item.faculty, item.major, item.year or 0, stream_number, stream)


class ScheduleService:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._lock = threading.Lock()
        self._refreshing = threading.Lock()
        self._lists: dict[str, ScheduleList] = {}
        self._fetched_at: float = 0
        self._cache_path = os.path.join(settings.data_dir, "schedules.json")
        self._load_disk()

    @property
    def updated_at(self) -> str | None:
        with self._lock:
            stamps = [value.updated_at for value in self._lists.values() if value.updated_at]
        return max(stamps) if stamps else None

    def _load_disk(self) -> None:
        try:
            with open(self._cache_path, encoding="utf-8") as handle:
                payload = json.load(handle)
            self._lists = {kind: ScheduleList.model_validate(payload[kind]) for kind in KINDS if kind in payload}
            self._fetched_at = float(payload.get("fetchedAt", 0))
        except (OSError, ValueError, KeyError):
            self._lists = {}

    def _save_disk(self) -> None:
        try:
            os.makedirs(self.settings.data_dir, exist_ok=True)
            payload = {kind: value.model_dump(by_alias=True) for kind, value in self._lists.items()}
            payload["fetchedAt"] = self._fetched_at
            temporary = self._cache_path + ".tmp"
            with open(temporary, "w", encoding="utf-8") as handle:
                json.dump(payload, handle, ensure_ascii=False)
            os.replace(temporary, self._cache_path)
        except OSError as error:
            logger.warning("Could not persist schedules: %s", error)

    def _query(self, client: httpx.Client, params: dict[str, str]) -> list[dict]:
        collected: list[dict] = []
        seen_cursors: set[str] = set()
        cursor: str | None = None
        for _ in range(self.settings.schedule_page_limit):
            query = dict(params, per_page=str(PAGE_SIZE))
            if cursor:
                query["cursor"] = cursor
            response = client.get(self.settings.schedules_api, params=query)
            response.raise_for_status()
            body = response.json()
            if not body.get("success", True):
                raise httpx.HTTPError(body.get("message") or "Schedule API failure")
            page = body.get("data") or {}
            collected.extend(page.get("data") or [])
            cursor = (page.get("meta") or {}).get("next_cursor")
            if not cursor or cursor in seen_cursors:
                break
            seen_cursors.add(cursor)
        return collected

    def _fetch_kind(self, client: httpx.Client, kind: ScheduleKind) -> list[ScheduleItem]:
        items: dict[int, ScheduleItem] = {}

        def absorb(rows: list[dict]) -> None:
            for raw in rows:
                item = normalize(raw, kind)
                if item is not None:
                    items[item.id or len(items) + 1_000_000] = item

        for degree in self.settings.degrees:
            overview = self._query(client, {"degree_type": degree, "type": kind})
            absorb(overview)
            slugs = list(dict.fromkeys([*FACULTY_SLUGS, *((raw.get("faculty") or {}).get("slug") for raw in overview)]))
            for slug in filter(None, slugs):
                rows = self._query(client, {"degree_type": degree, "type": kind, "faculty": slug})
                if len(rows) >= PAGE_SIZE:
                    logger.warning("Faculty %s (%s, %s) may be truncated at %s items", slug, degree, kind, len(rows))
                absorb(rows)
                time.sleep(0.1)
        return sorted(items.values(), key=sort_key)

    def _has(self, kind: ScheduleKind) -> bool:
        with self._lock:
            return kind in self._lists

    def refresh(self, wait: bool = False, kind: ScheduleKind | None = None) -> None:
        if not self._refreshing.acquire(blocking=wait):
            return
        try:
            if kind is not None and self._has(kind):
                return
            headers = {"User-Agent": self.settings.user_agent, "Accept": "application/json"}
            with httpx.Client(headers=headers, timeout=self.settings.request_timeout) as client:
                fresh: dict[str, ScheduleList] = {}
                for kind in KINDS:
                    try:
                        fresh[kind] = ScheduleList(updated_at=utc_now_iso(), items=self._fetch_kind(client, kind))
                    except (httpx.HTTPError, ValueError) as error:
                        logger.warning("Schedule refresh for %s failed: %s", kind, error)
            if fresh:
                with self._lock:
                    self._lists.update(fresh)
                    self._fetched_at = time.time()
                self._save_disk()
                logger.info("Schedules refreshed: %s", {kind: len(value.items) for kind, value in fresh.items()})
        finally:
            self._refreshing.release()

    def refresh_in_background(self) -> None:
        threading.Thread(target=self.refresh, name="schedule-refresh", daemon=True).start()

    def get(self, kind: ScheduleKind) -> ScheduleList:
        stale = time.time() - self._fetched_at > self.settings.schedule_ttl
        with self._lock:
            current = self._lists.get(kind)
        if current is None:
            self.refresh(wait=True, kind=kind)
            with self._lock:
                current = self._lists.get(kind)
        elif stale:
            self.refresh_in_background()
        return current or ScheduleList(updated_at=None, items=[])

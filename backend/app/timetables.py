import hashlib
import json
import logging
import os
import threading

import httpx

from . import errors
from .config import Settings
from .models import ScheduleItem, Timetable, TimetableLesson
from .schedules import KINDS, ScheduleService
from .timetable import TimetableError, parse

logger = logging.getLogger("uniapp.timetables")

PARSER_VERSION = 1


class TimetableService:
    def __init__(self, settings: Settings, schedules: ScheduleService) -> None:
        self.settings = settings
        self.schedules = schedules
        self._lock = threading.Lock()
        self._memory: dict[str, Timetable] = {}
        self._directory = os.path.join(settings.data_dir, "timetables")

    def _item(self, schedule_id: int) -> ScheduleItem:
        for kind in KINDS:
            for item in self.schedules.get(kind).items:
                if item.id == schedule_id:
                    return item
        raise errors.unknown_schedule()

    @staticmethod
    def _key(item: ScheduleItem) -> str:
        digest = hashlib.sha256(item.url.encode()).hexdigest()[:16]
        return f"{item.id}-{digest}-v{PARSER_VERSION}"

    def _read_disk(self, key: str) -> Timetable | None:
        try:
            with open(os.path.join(self._directory, f"{key}.json"), encoding="utf-8") as handle:
                return Timetable.model_validate(json.load(handle))
        except (OSError, ValueError):
            return None

    def _write_disk(self, key: str, timetable: Timetable) -> None:
        try:
            os.makedirs(self._directory, exist_ok=True)
            path = os.path.join(self._directory, f"{key}.json")
            with open(path + ".tmp", "w", encoding="utf-8") as handle:
                json.dump(timetable.model_dump(by_alias=True), handle, ensure_ascii=False)
            os.replace(path + ".tmp", path)
        except OSError as error:
            logger.warning("Could not persist timetable %s: %s", key, error)

    def _download(self, url: str) -> bytes:
        headers = {"User-Agent": self.settings.user_agent}
        try:
            with httpx.Client(headers=headers, timeout=self.settings.request_timeout, follow_redirects=True) as client:
                with client.stream("GET", url) as response:
                    response.raise_for_status()
                    chunks: list[bytes] = []
                    size = 0
                    for chunk in response.iter_bytes():
                        size += len(chunk)
                        if size > self.settings.timetable_max_bytes:
                            raise errors.schedule_unavailable()
                        chunks.append(chunk)
                    return b"".join(chunks)
        except httpx.HTTPError as error:
            logger.warning("Timetable download failed for %s: %s", url, error)
            raise errors.schedule_unavailable() from error

    def build(self, item: ScheduleItem, data: bytes) -> Timetable:
        try:
            lessons = parse(data)
        except TimetableError as error:
            logger.info("Timetable %s is unsupported: %s", item.id, error)
            lessons = []
        except Exception as error:
            logger.warning("Timetable %s crashed the parser: %s", item.id, error)
            lessons = []
        groups = sorted({group for lesson in lessons for group in lesson.groups}, key=lambda group: (len(group), group))
        return Timetable(
            schedule_id=item.id,
            status="ok" if len(lessons) >= 3 else "unsupported",
            url=item.url,
            week_one=self.settings.week_one,
            groups=groups,
            lessons=[TimetableLesson(**lesson.__dict__) for lesson in lessons] if len(lessons) >= 3 else [],
        )

    def get(self, schedule_id: int) -> Timetable:
        item = self._item(schedule_id)
        key = self._key(item)
        with self._lock:
            cached = self._memory.get(key)
        if cached is not None:
            return cached
        cached = self._read_disk(key)
        if cached is None:
            if not item.is_pdf or not item.url.lower().startswith("https://"):
                cached = Timetable(schedule_id=item.id, status="unsupported", url=item.url, week_one=self.settings.week_one)
            else:
                cached = self.build(item, self._download(item.url))
            self._write_disk(key, cached)
        with self._lock:
            self._memory[key] = cached
        return cached

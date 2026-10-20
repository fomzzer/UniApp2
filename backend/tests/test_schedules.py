import json
from pathlib import Path

from app.schedules import normalize, sort_key

FIXTURE = Path(__file__).parent / "fixtures" / "schedules_page.json"


def test_real_page_normalizes():
    payload = json.loads(FIXTURE.read_text(encoding="utf-8"))
    items = [normalize(raw, "lectures") for raw in payload["data"]["data"]]
    assert all(item is not None for item in items)
    first = items[0]
    assert first.faculty_slug == "faculty-of-computer-systems-and-technologies"
    assert first.year == 1
    assert first.stream == "1"
    assert first.is_pdf
    assert first.url.startswith("https://")


def test_external_links_are_not_pdf():
    raw = {
        "id": 7,
        "degree_type": "bachelor",
        "year": "2",
        "stream": 3,
        "file_path": None,
        "external_url": "https://programm.fdiba.tu-sofia.bg/bg/?q=plan_group",
        "faculty": {"slug": "f", "title": "Ф"},
        "major": {"slug": "m", "title": "М"},
    }
    item = normalize(raw, "exams")
    assert item.kind == "exams"
    assert item.year == 2
    assert not item.is_pdf


def test_incomplete_items_are_skipped():
    assert normalize({"id": 1, "faculty": {}, "major": {}}, "lectures") is None


def test_streams_sort_numerically():
    base = {"degree_type": "bachelor", "year": 1, "file_path": "https://x/a.pdf", "faculty": {"slug": "f", "title": "F"}, "major": {"slug": "m", "title": "M"}}
    items = [normalize({**base, "id": index, "stream": stream}, "lectures") for index, stream in enumerate([10, 2, 1])]
    assert [item.stream for item in sorted(items, key=sort_key)] == ["1", "2", "10"]


def test_get_waits_for_running_refresh(tmp_path):
    import threading
    import time as clock
    from dataclasses import replace

    from app.config import settings
    from app.models import ScheduleList
    from app.schedules import ScheduleService

    service = ScheduleService(replace(settings, data_dir=str(tmp_path)))
    calls = []

    def slow_fetch(client, kind):
        calls.append(kind)
        clock.sleep(0.3)
        return []

    service._fetch_kind = slow_fetch
    worker = threading.Thread(target=service.refresh)
    worker.start()
    clock.sleep(0.05)
    result = service.get("lectures")
    worker.join()
    assert isinstance(result, ScheduleList)
    assert result.updated_at is not None
    assert calls == ["lectures", "exams"]

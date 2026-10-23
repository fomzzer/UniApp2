from pathlib import Path

import pytest

from app.timetable import TimetableError, parse

FIXTURES = Path(__file__).parent / "fixtures"


def lessons(name):
    return parse((FIXTURES / name).read_bytes())


def find(items, day, start, group, week=None):
    return [lesson for lesson in items if lesson.day == day and lesson.start == start and group in lesson.groups and lesson.week == week]


def test_stream_lecture_covers_every_group():
    items = lessons("timetable_ksi.pdf")
    lecture = find(items, 0, "10:30", "37а")
    assert len(lecture) == 1
    assert lecture[0].subject == "МС"
    assert lecture[0].kind == "lecture"
    assert lecture[0].room == "1154"
    assert lecture[0].end == "13:15"
    assert lecture[0].groups == ["37а", "37б", "38а", "38б", "39а", "39б", "40а", "40б"]


def test_diagonal_cells_split_odd_and_even_weeks():
    items = lessons("timetable_ksi.pdf")
    odd = find(items, 0, "7:30", "37а", "odd")
    even = find(items, 0, "7:30", "38а", "even")
    assert [(lesson.subject, lesson.kind, lesson.room, lesson.end) for lesson in odd] == [("САА", "lab", "714", "10:15")]
    assert [(lesson.subject, lesson.kind, lesson.room) for lesson in even] == [("САА", "lab", "714")]
    assert not find(items, 0, "7:30", "38а", "odd")


def test_subgroup_rows_stay_separate():
    items = lessons("timetable_ksi.pdf")
    first = find(items, 0, "13:45", "37а")
    second = find(items, 0, "13:45", "37б")
    assert [(lesson.subject, lesson.room, lesson.end) for lesson in first] == [("ППЕ", "1437", "16:30")]
    assert [(lesson.subject, lesson.room) for lesson in second] == [("ППЕ", "1438")]


def test_two_hour_columns_split_into_hours():
    items = lessons("timetable_split_hours.pdf")
    lab = find(items, 2, "8:30", "30б", "odd")
    assert [(lesson.subject, lesson.kind, lesson.room, lesson.end) for lesson in lab] == [("КУК", "seminar", "4314", "10:15")]
    assert [(lesson.subject, lesson.kind) for lesson in find(items, 2, "8:30", "30б", "even")] == [("КУК", "lab")]
    lecture = find(items, 3, "8:30", "30а")
    assert [(lesson.subject, lesson.room, lesson.end) for lesson in lecture] == [("ПМТ", "4224", "11:15")]


def test_weekly_tables_are_unsupported():
    with pytest.raises(TimetableError):
        lessons("timetable_weekly.pdf")


def test_garbage_is_rejected():
    with pytest.raises(TimetableError):
        parse(b"not a pdf")

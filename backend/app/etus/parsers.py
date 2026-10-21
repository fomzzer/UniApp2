import copy
import re
from dataclasses import dataclass, field

from bs4 import BeautifulSoup

from ..models import Attempt, Dormitory, Grades, Semester, Student, Subject

GRADE_PATTERN = re.compile(
    r"((?:Слаб|Среден|Добър|Мн\.\s*добър|Много\s*добър|Отличен))\s*\((\d)\)\s*\((редовна|поправителна|ликвидационна)\)"
    r"(?:[^\n]*?от\s*(\d{2})\.(\d{2})\.(\d{4}))?",
    re.IGNORECASE,
)
SEMESTER_PATTERN = re.compile(r"^(\d+)\s*сем\.?\s*(.*)$", re.IGNORECASE)
CURRENT_MARK = re.compile(r"^\(\s*текущ\s*\)\s*", re.IGNORECASE)
CREDITED_MARK = "зачита се"
ATTEMPT_KINDS = ("редовна", "поправителна", "ликвидационна")


@dataclass(frozen=True)
class ParsedAttempt:
    kind: str
    grade: int
    label: str
    date: str | None = None


@dataclass
class GradeRow:
    subject: str
    control: str
    attempts: list[ParsedAttempt] = field(default_factory=list)
    credited: bool = False


@dataclass
class SemesterRows:
    title: str
    number: int | None
    current: bool = False
    rows: list[GradeRow] = field(default_factory=list)


def clean(text: str | None) -> str:
    if not text:
        return ""
    return re.sub(r"\s+", " ", text.replace("\xa0", " ")).strip()


def parse_student_name(soup: BeautifulSoup) -> str:
    logout = soup.find("input", id="izh")
    if logout is None or logout.parent is None:
        return ""
    return clean(logout.parent.get_text(" ", strip=True))


def parse_info(soup: BeautifulSoup) -> dict[str, str]:
    info: dict[str, str] = {}
    table = soup.find("table", id="info")
    if table is None:
        return info
    for row in table.find_all("tr"):
        cells = row.find_all("td")
        for index in range(0, len(cells) - 1, 2):
            keys = [_info_key(part) for part in cells[index].stripped_strings]
            keys = [key for key in keys if key]
            values = [clean(part).replace('"', "") for part in cells[index + 1].stripped_strings]
            values = [value for value in values if value]
            if not keys:
                continue
            if len(keys) > 1 and len(values) >= len(keys):
                info.update(zip(keys, values))
            else:
                info[keys[0]] = values[0] if values else ""
    return info


def _info_key(text: str) -> str:
    return clean(text).replace('"', "").rstrip(":").strip()


def _pick(info: dict[str, str], *needles: str) -> str | None:
    for key, value in info.items():
        lowered = key.lower()
        if value and any(needle in lowered for needle in needles):
            return value
    return None


def _int_from(text: str | None) -> int | None:
    if not text:
        return None
    match = re.search(r"\d+", text)
    return int(match.group()) if match else None


EMAIL_PATTERN = re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+")


def _email(text: str | None) -> str | None:
    if not text:
        return None
    match = EMAIL_PATTERN.search(text)
    return match.group() if match else None


UNIVERSITY_DOMAIN = "tu-sofia.bg"


def _university_email(info: dict[str, str]) -> str | None:
    emails = [match.group() for value in info.values() for match in EMAIL_PATTERN.finditer(value)]
    university = [email for email in emails if email.lower().endswith(UNIVERSITY_DOMAIN)]
    if university:
        return university[0]
    return _email(_pick(info, "имейл", "e-mail", "email", "поща")) or (emails[0] if emails else None)


def build_student(name: str, faculty_no: str, info: dict[str, str]) -> Student:
    semester = _int_from(_pick(info, "семест"))
    course = (semester + 1) // 2 if semester else None
    return Student(
        name=name or _pick(info, "име") or faculty_no,
        faculty_no=_pick(info, "фак. номер", "факултетен номер", "фак. №") or faculty_no,
        ean=info.get("ЕАН") or _pick(info, "еан"),
        faculty=_pick(info, "факултет"),
        specialty=_pick(info, "специалност"),
        degree=_pick(info, "степен", "окс"),
        education_form=_pick(info, "вид обучение", "форма на обучение"),
        semester=semester,
        course=course,
        group=_pick(info, "група"),
        stream=_pick(info, "поток"),
        email=_university_email(info),
        details=info,
    )


def _find_grades_table(soup: BeautifulSoup):
    for table in soup.find_all("table"):
        text = table.get_text(" ", strip=True).lower()
        if "дисциплина" in text and ("лекции" in text or "оценка" in text):
            return table
    return None


def _attempts(text: str) -> list[ParsedAttempt]:
    attempts: list[ParsedAttempt] = []
    for match in GRADE_PATTERN.finditer(text):
        label, value, kind, day, month, year = match.groups()
        attempts.append(
            ParsedAttempt(
                kind="regular" if kind.lower() == "редовна" else "retake",
                grade=int(value),
                label=clean(label),
                date=f"{year}-{month}-{day}" if year else None,
            )
        )
    return attempts


def _grade_row(name: str, remainder: str, attempts_text: str) -> GradeRow | None:
    if not name:
        return None
    control_match = re.search(r"\(([^()]*?)\)", remainder)
    control = clean(control_match.group(1)) if control_match else ""
    if control.isdigit() or control.lower() in ATTEMPT_KINDS or control.lower() == CREDITED_MARK:
        control = ""
    row = GradeRow(
        subject=name,
        control=control,
        attempts=_attempts(attempts_text),
        credited=CREDITED_MARK in remainder.lower(),
    )
    if not row.control and not row.attempts and not row.credited:
        return None
    return row


def _own_cell(cell):
    own = copy.copy(cell)
    for nested in own.find_all(["tr", "td", "th", "table"]):
        nested.decompose()
    return own


def _row_from_cell(cell) -> GradeRow | None:
    bold = cell.find("b")
    multiline = cell.get_text("\n", strip=True)
    if bold is None:
        return _row_from_text(clean(cell.get_text(" ", strip=True)), multiline)
    name = clean(bold.get_text(" ", strip=True))
    flat = clean(cell.get_text(" ", strip=True))
    remainder = flat[flat.find(name) + len(name):] if name in flat else flat
    return _grade_row(name, remainder, multiline)


def _row_from_text(flat: str, multiline: str) -> GradeRow | None:
    if "(" not in flat and CREDITED_MARK not in flat.lower():
        return None
    name = clean(flat.split("(")[0])
    return _grade_row(name, flat[len(name):], multiline)


def parse_grade_rows(soup: BeautifulSoup) -> list[SemesterRows]:
    table = _find_grades_table(soup)
    if table is None:
        return []
    semesters: list[SemesterRows] = []
    current: SemesterRows | None = None
    for row in table.find_all("tr"):
        cells = row.find_all("td")
        if not cells:
            continue
        cell = _own_cell(cells[0])
        flat = clean(cell.get_text(" ", strip=True))
        semester_match = SEMESTER_PATTERN.match(flat)
        grade_row: GradeRow | None
        if semester_match:
            number = int(semester_match.group(1))
            rest = semester_match.group(2).strip()
            is_current = bool(CURRENT_MARK.match(rest))
            rest = CURRENT_MARK.sub("", rest).strip()
            current = SemesterRows(title=f"{number} сем.", number=number, current=is_current)
            semesters.append(current)
            if not rest:
                continue
            grade_row = _row_from_text(rest, rest)
        else:
            grade_row = _row_from_cell(cell)
        if grade_row is None:
            continue
        if current is None:
            current = SemesterRows(title="Общи", number=None)
            semesters.append(current)
        current.rows.append(grade_row)
    return semesters


def _merge_rows(rows: list[GradeRow]) -> list[Subject]:
    merged: dict[tuple[str, str], GradeRow] = {}
    order: list[tuple[str, str]] = []
    for row in rows:
        key = (row.subject.lower(), row.control.lower())
        if key not in merged:
            merged[key] = GradeRow(subject=row.subject, control=row.control)
            order.append(key)
        target = merged[key]
        target.credited = target.credited or row.credited
        for attempt in row.attempts:
            if attempt not in target.attempts:
                target.attempts.append(attempt)
    subjects: list[Subject] = []
    for key in order:
        row = merged[key]
        ranked = sorted(
            enumerate(row.attempts),
            key=lambda pair: (0 if pair[1].kind == "regular" else 1, pair[1].date or "", pair[0]),
        )
        ordered = [attempt for _, attempt in ranked]
        final = ordered[-1] if ordered else None
        subjects.append(
            Subject(
                name=row.subject,
                control=row.control or None,
                grade=final.grade if final else None,
                label=final.label if final else None,
                credited=row.credited and final is None,
                attempts=[
                    Attempt(kind=attempt.kind, grade=attempt.grade, label=attempt.label, date=attempt.date)
                    for attempt in ordered
                ],
            )
        )
    return subjects


def _average(values: list[int]) -> float | None:
    if not values:
        return None
    return round(sum(values) / len(values), 2)


def build_grades(semester_rows: list[SemesterRows]) -> Grades:
    semesters: list[Semester] = []
    all_grades: list[int] = []
    credited = 0
    for block in semester_rows:
        subjects = _merge_rows(block.rows)
        values = [subject.grade for subject in subjects if subject.grade is not None]
        all_grades.extend(values)
        credited += sum(1 for subject in subjects if subject.credited)
        if subjects:
            semesters.append(
                Semester(
                    number=block.number,
                    title=block.title,
                    current=block.current,
                    average=_average(values),
                    subjects=subjects,
                )
            )
    semesters.sort(key=lambda item: item.number if item.number is not None else -1, reverse=True)
    distribution = {str(value): all_grades.count(value) for value in range(6, 1, -1)}
    return Grades(
        gpa=_average(all_grades),
        graded_count=len(all_grades),
        credited_count=credited,
        distribution=distribution,
        semesters=semesters,
    )


def legacy_grade_rows(semester_rows: list[SemesterRows]) -> list[dict]:
    result: list[dict] = []
    for block in semester_rows:
        result.append({"is_semester": True, "title": block.title})
        for row in block.rows:
            regular = next((f"{item.label} ({item.grade})" for item in row.attempts if item.kind == "regular"), "-")
            retake = next((f"{item.label} ({item.grade})" for item in reversed(row.attempts) if item.kind == "retake"), "-")
            final = retake if retake != "-" else regular
            if row.credited and final == "-":
                regular = final = "Зачита се"
            result.append({"subject": row.subject, "type": row.control, "regular": regular, "retake": retake, "final": final})
    return result


NAVIGATION_KEYWORDS = (
    "информация",
    "здравно осигуряване",
    "заверки и оценки",
    "спорт",
    "стипендии",
    "плащания",
    "идентификация",
)


def parse_dormitory(soup: BeautifulSoup) -> Dormitory:
    message = ""
    header = soup.find(
        lambda tag: tag.name in ("b", "h1", "h2", "h3", "div", "font") and "общежития" in tag.get_text().lower()
    )
    if header is not None:
        candidate_tag = header.find_next(["p", "div", "font"])
        if candidate_tag is not None:
            candidate = clean(candidate_tag.get_text(" ", strip=True))
            if len(candidate) > 5 and "общежития" not in candidate.lower():
                message = candidate
    if not message or "здравно осигуряване" in message.lower():
        message = ""
        for tag in soup.find_all(["p", "font", "div"]):
            text = clean(tag.get_text(" ", strip=True))
            lowered = text.lower()
            if len(text) <= 10 or text.startswith("[") or "университет" in lowered:
                continue
            if sum(1 for keyword in NAVIGATION_KEYWORDS if keyword in lowered) < 2:
                message = text
                break
    if not message:
        return Dormitory(status=None, accommodated=False)
    lowered = message.lower()
    accommodated = "настанен" in lowered and "не е настанен" not in lowered and "ненастанен" not in lowered
    return Dormitory(status=message, accommodated=accommodated)


def parse_failure_reason(soup: BeautifulSoup) -> str:
    keywords = ("грешн", "невалид", "грешен", "error", "опита", "отказан", "изображ")
    tag = soup.find(
        lambda item: item.name in ("font", "div", "p", "b", "span")
        and any(keyword in item.get_text().lower() for keyword in keywords)
        and len(item.get_text(strip=True)) < 400
    )
    return clean(tag.get_text(" ", strip=True)) if tag is not None else ""

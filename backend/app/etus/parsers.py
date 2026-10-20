import re
from dataclasses import dataclass, field

from bs4 import BeautifulSoup

from ..models import Attempt, Dormitory, Grades, Semester, Student, Subject

GRADE_PATTERN = re.compile(
    r"((?:Слаб|Среден|Добър|Мн\.\s*добър|Много\s*добър|Отличен))\s*\((\d)\)\s*\((редовна|поправителна|ликвидационна)\)",
    re.IGNORECASE,
)
SEMESTER_PATTERN = re.compile(r"^(\d+)\s*сем\.?\s*(.*)$", re.IGNORECASE)
CREDITED_MARK = "зачита се"


@dataclass
class GradeRow:
    subject: str
    control: str
    attempts: list[tuple[str, int, str]] = field(default_factory=list)
    credited: bool = False


@dataclass
class SemesterRows:
    title: str
    number: int | None
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
            key_parts = list(cells[index].stripped_strings)
            value_parts = list(cells[index + 1].stripped_strings)
            key = clean(key_parts[0]).replace('"', "").rstrip(":").strip() if key_parts else ""
            value = clean(" ".join(value_parts)).replace('"', "") if value_parts else ""
            if key:
                info[key] = value
    return info


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


def build_student(name: str, faculty_no: str, info: dict[str, str]) -> Student:
    semester = _int_from(_pick(info, "семест"))
    course = (semester + 1) // 2 if semester else None
    return Student(
        name=name or _pick(info, "име") or faculty_no,
        faculty_no=_pick(info, "фак. номер", "факултетен номер", "фак. №") or faculty_no,
        faculty=_pick(info, "факултет"),
        specialty=_pick(info, "специалност"),
        degree=_pick(info, "степен", "окс"),
        education_form=_pick(info, "вид обучение", "форма на обучение"),
        semester=semester,
        course=course,
        group=_pick(info, "група"),
        stream=_pick(info, "поток"),
        email=_pick(info, "имейл", "e-mail", "email"),
        details=info,
    )


def _find_grades_table(soup: BeautifulSoup):
    for table in soup.find_all("table"):
        text = table.get_text(" ", strip=True).lower()
        if "дисциплина" in text and ("лекции" in text or "оценка" in text):
            return table
    return None


def parse_grade_rows(soup: BeautifulSoup) -> list[SemesterRows]:
    table = _find_grades_table(soup)
    if table is None:
        return []
    semesters: list[SemesterRows] = []
    current: SemesterRows | None = None
    for row in table.find_all("tr")[1:]:
        cells = row.find_all("td")
        if not cells:
            continue
        text = clean(cells[0].get_text(" ", strip=True))
        semester_match = SEMESTER_PATTERN.match(text)
        if semester_match:
            number = int(semester_match.group(1))
            current = SemesterRows(title=f"{number} сем.", number=number)
            semesters.append(current)
            text = semester_match.group(2).strip()
        if not text:
            continue
        lowered = text.lower()
        if "(" not in text and CREDITED_MARK not in lowered:
            continue
        subject = clean(text.split("(")[0])
        if not subject:
            continue
        control_match = re.search(r"\(([^()]*?)\)", text)
        control = clean(control_match.group(1)) if control_match else ""
        if control.isdigit() or control.lower() in ("редовна", "поправителна", "ликвидационна"):
            control = ""
        grade_row = GradeRow(subject=subject, control=control)
        if CREDITED_MARK in lowered:
            grade_row.credited = True
        for label, value, kind in GRADE_PATTERN.findall(text):
            attempt_kind = "regular" if kind.lower() == "редовна" else "retake"
            grade_row.attempts.append((attempt_kind, int(value), clean(label)))
        if not grade_row.control and not grade_row.attempts and not grade_row.credited:
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
        attempts = sorted(row.attempts, key=lambda item: 0 if item[0] == "regular" else 1)
        final = attempts[-1] if attempts else None
        subjects.append(
            Subject(
                name=row.subject,
                control=row.control or None,
                grade=final[1] if final else None,
                label=final[2] if final else None,
                credited=row.credited and final is None,
                attempts=[Attempt(kind=kind, grade=value, label=label) for kind, value, label in attempts],
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
            semesters.append(Semester(number=block.number, title=block.title, average=_average(values), subjects=subjects))
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
            regular = next((f"{label} ({value})" for kind, value, label in row.attempts if kind == "regular"), "-")
            retake = next((f"{label} ({value})" for kind, value, label in row.attempts if kind == "retake"), "-")
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

import io
import re
from dataclasses import dataclass, field

import pdfplumber

TIME = re.compile(r"(\d{1,2})[:.](\d{2})")
GROUP = re.compile(r"^(\d{1,4})([а-д]?)(?![\dа-д])")
ROOM = re.compile(r"^\d{3,5}[а-яА-Яa-zA-Z]{0,2}(?:[,/]\d{3,5}[а-яА-Яa-zA-Z]{0,2})*\*{0,5}[,;]?$")
JOINED = re.compile(r"^(л\.?у|с\.?у|лб|лу|су|л|lab|lec|tut)\.?,?(\d{3,5}[а-яА-Яa-zA-Z]{0,2})$", re.IGNORECASE)
DAYS = {
    "понеделник": 0, "вторник": 1, "сряда": 2, "четвъртък": 3, "петък": 4, "събота": 5, "неделя": 6,
    "lun": 0, "mar": 1, "mer": 2, "jeu": 3, "ven": 4, "sam": 5,
    "lundi": 0, "mardi": 1, "mercredi": 2, "jeudi": 3, "vendredi": 4, "samedi": 5,
    "mon": 0, "tue": 1, "wed": 2, "thu": 3, "fri": 4, "sat": 5,
    "monday": 0, "tuesday": 1, "wednesday": 2, "thursday": 3, "friday": 4, "saturday": 5,
    "montag": 0, "dienstag": 1, "mittwoch": 2, "donnerstag": 3, "freitag": 4, "samstag": 5,
}
KINDS = {
    "л": "lecture", "лек": "lecture", "c": "lecture", "v": "lecture",
    "лб": "lab", "лу": "lab", "tp": "lab", "ü": "lab",
    "су": "seminar", "td": "seminar",
    "lec": "lecture", "lab": "lab", "tut": "seminar", "sem": "seminar",
}
LATIN_TO_CYRILLIC = str.maketrans("aAbBeEoOpPcCxX", "аАбБеЕоОрРсСхХ")
LOOKALIKES = str.maketrans("aAeEoOpPcCxXyBHKMT", "аАеЕоОрРсСхХуВНКМТ")
TOLERANCE = 2.0


class TimetableError(ValueError):
    pass


@dataclass
class Column:
    left: float
    right: float
    start: str
    end: str


@dataclass
class Row:
    top: float
    bottom: float
    day: int
    group: str | None


@dataclass
class Lesson:
    day: int
    start: str
    end: str
    groups: list[str]
    subject: str
    kind: str | None
    room: str | None
    week: str | None
    text: str
    notes: list[str] = field(default_factory=list)


def _center(item: dict) -> tuple[float, float]:
    return (item["x0"] + item["x1"]) / 2, (item["top"] + item["bottom"]) / 2


def _rotated(char: dict) -> bool:
    return abs(char["matrix"][1]) > 0.5 or not char.get("upright", True)


def _minutes(value: str) -> int:
    hours, minutes = value.split(":")
    return int(hours) * 60 + int(minutes)


def _clock(minutes: int) -> str:
    return f"{minutes // 60}:{minutes % 60:02d}"


def _distinct(values, gap: float = TOLERANCE * 2) -> list[float]:
    result: list[float] = []
    for value in sorted(values):
        if not result or value - result[-1] > gap:
            result.append(value)
    return result


def _day(text: str) -> int | None:
    cleaned = re.sub(r"[^a-zа-яё]", "", text.lower())
    if len(cleaned) < 3:
        return None
    if cleaned in DAYS:
        return DAYS[cleaned]
    for name, day in DAYS.items():
        if len(name) >= 5 and (cleaned.startswith(name) or name.startswith(cleaned) and len(cleaned) >= 5):
            return day
    return None


def _group(text: str) -> str | None:
    first = text.split("\n")[0]
    cleaned = re.sub(r"\s+", "", first).replace("ª", "a").replace("ᵃ", "a").replace("ᵇ", "b").translate(LATIN_TO_CYRILLIC).lower()
    cleaned = re.sub(r"^([а-д])(\d{1,4})", r"\2\1", cleaned)
    match = GROUP.match(cleaned)
    return match.group(1) + match.group(2) if match else None


class _Page:
    def __init__(self, page) -> None:
        self.words = [word for word in page.extract_words(extra_attrs=["size", "upright"]) if word["upright"]]
        self.chars = [char for char in page.chars if char["text"].strip()]
        self.horizontal: list[tuple[float, float, float]] = []
        self.vertical: list[tuple[float, float, float]] = []
        self.diagonals: list[tuple[float, float, float, float]] = []
        for edge in page.edges:
            x0, x1, top, bottom = edge["x0"], edge["x1"], edge["top"], edge["bottom"]
            if bottom - top <= TOLERANCE and x1 - x0 > TOLERANCE:
                self.horizontal.append(((top + bottom) / 2, x0, x1))
            elif x1 - x0 <= TOLERANCE and bottom - top > TOLERANCE:
                self.vertical.append(((x0 + x1) / 2, top, bottom))
        for shape in [*page.curves, *page.lines]:
            points = shape.get("pts") or []
            if len(points) < 2:
                continue
            left = min(x for x, _ in points)
            right = max(x for x, _ in points)
            if right - left <= 6:
                continue
            near_left = [y for x, y in points if x - left <= 2.5]
            near_right = [y for x, y in points if right - x <= 2.5]
            ay, by = sum(near_left) / len(near_left), sum(near_right) / len(near_right)
            if abs(ay - by) > 6:
                self.diagonals.append((left, ay, right, by))

    def has_vertical(self, x: float, y: float) -> bool:
        return any(abs(vx - x) <= TOLERANCE and top - TOLERANCE <= y <= bottom + TOLERANCE for vx, top, bottom in self.vertical)

    def has_horizontal(self, y: float, x: float) -> bool:
        return any(abs(hy - y) <= TOLERANCE and left - TOLERANCE <= x <= right + TOLERANCE for hy, left, right in self.horizontal)

    def verticals_through(self, y: float, left: float = -1e9, right: float = 1e9) -> list[float]:
        return _distinct(x for x, top, bottom in self.vertical if top - TOLERANCE <= y <= bottom + TOLERANCE and left - TOLERANCE <= x <= right + TOLERANCE)

    def horizontals_through(self, x: float, top: float, bottom: float) -> list[float]:
        return _distinct(y for y, left, right in self.horizontal if left - TOLERANCE <= x <= right + TOLERANCE and top - TOLERANCE <= y <= bottom + TOLERANCE)

    def text_in(self, left: float, right: float, top: float, bottom: float) -> str:
        chars = [char for char in self.chars if left <= _center(char)[0] <= right and top <= _center(char)[1] <= bottom]
        lines: list[list[dict]] = []
        for char in sorted((char for char in chars if not _rotated(char)), key=lambda char: char["top"]):
            line = lines[-1] if lines else None
            if line and char["top"] < max(item["bottom"] for item in line) - 0.3 * (char["bottom"] - char["top"]):
                line.append(char)
            else:
                lines.append([char])
        upright = "\n".join("".join(char["text"] for char in sorted(line, key=lambda char: char["x0"])) for line in lines)
        rotated = sorted((char for char in chars if _rotated(char)), key=lambda char: -char["top"] if char["matrix"][1] > 0 else char["top"])
        return upright + "".join(char["text"] for char in rotated)

    def header(self) -> tuple[list[tuple[float, float, int, int]], float]:
        tokens: list[tuple[dict, int]] = []
        for word in self.words:
            for match in TIME.finditer(word["text"]):
                hours, minutes = int(match.group(1)), int(match.group(2))
                if 6 <= hours <= 23 and minutes < 60:
                    tokens.append((word, hours * 60 + minutes))
        if len(tokens) < 6:
            raise TimetableError("no time header")
        rows: dict[int, list] = {}
        for word, minutes in tokens:
            rows.setdefault(round(word["top"] / 6), []).append((word, minutes))
        header_top = min(word["top"] for word, _ in max(rows.values(), key=len))
        header = [(word, minutes) for word, minutes in tokens if -8 <= word["top"] - header_top < 30]
        header_bottom = max(word["bottom"] for word, _ in header)
        boundaries = self.verticals_through((header_top + header_bottom) / 2)
        blocks: list[tuple[float, float, int, int]] = []
        for left, right in zip(boundaries, boundaries[1:]):
            inside = sorted(
                ((word, minutes) for word, minutes in header if left <= _center(word)[0] <= right),
                key=lambda pair: (round(pair[0]["top"] / 3), pair[0]["x0"]),
            )
            if len(inside) >= 2 and inside[-1][1] > inside[0][1]:
                blocks.append((left, right, inside[0][1], inside[-1][1]))
        if len(blocks) < 4:
            raise TimetableError("no time slots")
        return blocks, header_bottom

    def columns(self, blocks: list[tuple[float, float, int, int]], body_top: float, body_bottom: float) -> list[Column]:
        left_edge, right_edge = blocks[0][0], blocks[-1][1]
        xs = _distinct(
            x for x, top, bottom in self.vertical
            if left_edge - TOLERANCE <= x <= right_edge + TOLERANCE and bottom > body_top + 4 and top < body_bottom - 4
        )
        xs = _distinct([*xs, *(block[0] for block in blocks), right_edge])
        columns: list[Column] = []
        for left, right in zip(xs, xs[1:]):
            block = next((block for block in blocks if block[0] - TOLERANCE <= left and right <= block[1] + TOLERANCE), None)
            if block is None:
                continue
            block_left, block_right, start, end = block
            hours = max(1, round((end - start + 15) / 60))
            first = round((left - block_left) / (block_right - block_left) * hours)
            last = max(first, round((right - block_left) / (block_right - block_left) * hours) - 1)
            if hours == 1:
                columns.append(Column(left, right, _clock(start), _clock(end)))
            else:
                columns.append(Column(left, right, _clock(start + 60 * first), _clock(min(end, start + 60 * last + 45))))
        return columns

    def rows(self, first_left: float, body_top: float) -> list[Row]:
        body_bottom = max(y for y, left, right in self.horizontal if left < first_left < right)
        lefts = self.verticals_through((body_top + body_bottom) / 2, right=first_left)
        label_columns = [(left, right) for left, right in zip(lefts, lefts[1:]) if right - left > 6]
        if not label_columns:
            raise TimetableError("no label column")
        bands: dict[tuple[float, float], list[tuple[float, float, str]]] = {}
        for left, right in label_columns:
            ys = self.horizontals_through((left + right) / 2, body_top, body_bottom)
            bands[(left, right)] = [(top, bottom, self.text_in(left, right, top, bottom)) for top, bottom in zip(ys, ys[1:]) if bottom - top > 4]
        day_column = max(label_columns, key=lambda column: sum(_day(text) is not None for _, _, text in bands[column]))
        if not any(_day(text) is not None for _, _, text in bands[day_column]):
            raise TimetableError("no days")
        group_column = max(label_columns, key=lambda column: sum(_group(text) is not None for _, _, text in bands[column]))
        if not any(_group(text) is not None for _, _, text in bands[group_column]):
            group_column = day_column
        days = [(top, bottom, _day(text)) for top, bottom, text in bands[day_column] if _day(text) is not None]
        rows: list[Row] = []
        for top, bottom, text in bands[group_column]:
            middle = (top + bottom) / 2
            day = next((day for day_top, day_bottom, day in days if day_top - TOLERANCE <= middle <= day_bottom + TOLERANCE), None)
            if day is not None:
                rows.append(Row(top, bottom, day, _group(text) if group_column != day_column else None))
        return rows


def _lines(words: list[dict]) -> list[list[dict]]:
    lines: list[list[dict]] = []
    for word in sorted(words, key=lambda word: (word["top"], word["x0"])):
        if lines and abs(lines[-1][0]["top"] - word["top"]) < max(2.5, word["size"] * 0.4):
            lines[-1].append(word)
        else:
            lines.append([word])
    return [sorted(line, key=lambda word: word["x0"]) for line in lines]


def _cyrillic(token: str) -> str:
    if re.search(r"[а-яА-ЯёЁ]", token):
        return token.translate(LOOKALIKES)
    return token


def _kind(token: str) -> str | None:
    return KINDS.get(re.sub(r"[.,;:]", "", token.lower()))


def describe(words: list[dict]) -> list[tuple[str, str | None, str | None, list[str]]]:
    biggest = max(word["size"] for word in words)
    main = [word for word in words if word["size"] >= biggest * 0.8]
    meta = [word for word in words if word["size"] < biggest * 0.8]
    tokens: list[str] = []
    for line in _lines(main):
        for word in line:
            joined = JOINED.match(word["text"])
            tokens.extend([joined.group(1), joined.group(2)] if joined else [word["text"]])
    entries: list[dict] = []
    current: dict = {"subject": [], "kind": None, "rooms": [], "place": []}
    for token in tokens:
        kind = _kind(token)
        if current["rooms"] and not ROOM.match(token):
            entries.append(current)
            current = {"subject": [], "kind": None, "rooms": [], "place": []}
        if kind and current["subject"] and current["kind"] is None:
            current["kind"] = kind
        elif ROOM.match(token) and current["subject"] and not current["place"]:
            current["rooms"].append(token.rstrip(",;*"))
        elif current["kind"] and not current["rooms"]:
            current["place"].append(token)
        else:
            current["subject"].append(token)
    entries.append(current)
    notes: list[str] = []
    for line in _lines(meta):
        parts = [word["text"] for word in line]
        if parts and ROOM.match(parts[0]) and not entries[-1]["rooms"]:
            entries[-1]["rooms"].append(parts[0].rstrip(",;*"))
            parts = parts[1:]
        if parts:
            notes.append(" ".join(parts))
    result = []
    for entry in entries:
        subject = " ".join(_cyrillic(token) for token in entry["subject"]).strip(" ,;-")
        if subject or entry["rooms"]:
            room = ", ".join(entry["rooms"]) or " ".join(entry["place"]).strip(" ,;") or None
            result.append((subject, entry["kind"], room, notes))
    return result


def parse(data: bytes) -> list[Lesson]:
    try:
        document = pdfplumber.open(io.BytesIO(data))
    except Exception as error:
        raise TimetableError(f"unreadable pdf: {error}") from error
    with document:
        if not document.pages:
            raise TimetableError("empty pdf")
        page = _Page(document.pages[0])
        blocks, header_bottom = page.header()
        rows = page.rows(blocks[0][0], header_bottom)
        if not rows:
            raise TimetableError("no rows")
        columns = page.columns(blocks, rows[0].top, rows[-1].bottom)
        return _lessons(page, columns, rows)


def _lessons(page: _Page, columns: list[Column], rows: list[Row]) -> list[Lesson]:
    parent = {(r, c): (r, c) for r in range(len(rows)) for c in range(len(columns))}

    def find(cell):
        while parent[cell] != cell:
            parent[cell] = parent[parent[cell]]
            cell = parent[cell]
        return cell

    for r, row in enumerate(rows):
        middle = (row.top + row.bottom) / 2
        for c in range(len(columns) - 1):
            if not page.has_vertical(columns[c].right, middle):
                parent[find((r, c))] = find((r, c + 1))
    for r in range(len(rows) - 1):
        if rows[r].day != rows[r + 1].day or abs(rows[r].bottom - rows[r + 1].top) > TOLERANCE * 2:
            continue
        for c, column in enumerate(columns):
            if not page.has_horizontal(rows[r].bottom, (column.left + column.right) / 2):
                parent[find((r, c))] = find((r + 1, c))

    regions: dict[tuple[int, int], list[tuple[int, int]]] = {}
    for cell in parent:
        regions.setdefault(find(cell), []).append(cell)

    contents: dict[tuple[int, int], list[dict]] = {}
    for word in page.words:
        x, y = _center(word)
        row = next((index for index, row in enumerate(rows) if row.top <= y <= row.bottom), None)
        column = next((index for index, column in enumerate(columns) if column.left <= x <= column.right), None)
        if row is not None and column is not None:
            contents.setdefault(find((row, column)), []).append(word)

    lessons: list[Lesson] = []
    for root, cells in regions.items():
        words = contents.get(root)
        if not words:
            continue
        row_indexes = sorted({r for r, _ in cells})
        column_indexes = sorted({c for _, c in cells})
        left, right = columns[column_indexes[0]].left, columns[column_indexes[-1]].right
        top, bottom = rows[row_indexes[0]].top, rows[row_indexes[-1]].bottom
        slack = TOLERANCE * 3
        diagonals = [
            diagonal for diagonal in page.diagonals
            if left - slack <= diagonal[0] and diagonal[2] <= right + slack
            and top - slack <= min(diagonal[1], diagonal[3]) and max(diagonal[1], diagonal[3]) <= bottom + slack
        ]
        parts: list[tuple[str | None, list[dict], list[int], list[int]]] = []
        if diagonals:
            claimed: set[int] = set()
            for ax, ay, bx, by in sorted(diagonals, key=lambda diagonal: min(diagonal[1], diagonal[3])):
                span_rows = [r for r in row_indexes if rows[r].bottom > min(ay, by) + TOLERANCE and rows[r].top < max(ay, by) - TOLERANCE] or row_indexes
                span_columns = [c for c in column_indexes if columns[c].right > ax + TOLERANCE and columns[c].left < bx - TOLERANCE] or column_indexes
                above: list[dict] = []
                below: list[dict] = []
                for word in words:
                    x, y = _center(word)
                    if id(word) in claimed or not min(ay, by) - 8 <= y <= max(ay, by) + 8 or not ax - 4 <= x <= bx + 4:
                        continue
                    line_y = ay + (by - ay) * (x - ax) / (bx - ax)
                    (above if y < line_y else below).append(word)
                    claimed.add(id(word))
                parts.append(("odd", above, span_rows, span_columns))
                parts.append(("even", below, span_rows, span_columns))
            rest = [word for word in words if id(word) not in claimed]
            if rest:
                parts.append((None, rest, row_indexes, column_indexes))
        else:
            parts.append((None, words, row_indexes, column_indexes))
        for week, part, span_rows, span_columns in parts:
            if not part:
                continue
            groups = list(dict.fromkeys(rows[r].group for r in span_rows if rows[r].group))
            text = " / ".join(" ".join(word["text"] for word in line) for line in _lines(part))
            for subject, kind, room, notes in describe(part):
                lessons.append(Lesson(
                    day=rows[span_rows[0]].day,
                    start=columns[span_columns[0]].start,
                    end=columns[span_columns[-1]].end,
                    groups=groups,
                    subject=subject,
                    kind=kind,
                    room=room,
                    week=week,
                    text=text,
                    notes=notes,
                ))
    lessons.sort(key=lambda lesson: (lesson.day, _minutes(lesson.start), lesson.groups, lesson.week or ""))
    return lessons

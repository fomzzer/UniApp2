from bs4 import BeautifulSoup

from app.etus import parsers

HOME_PAGE = """
<html><body>
<div>Иван Петров Иванов <input type=submit id=izh value="Изход"></div>
<table id=info>
<tr><td><b>Фак. номер:</b><br><b>ЕАН:</b></td><td>121221089<br><a href="ean.php">AB12345</a></td><td>Факултет:</td><td>Факултет Компютърни системи и технологии</td></tr>
<tr><td>Специалност:</td><td>Компютърно и софтуерно инженерство</td><td>Записан семестър:</td><td>3</td></tr>
<tr><td>Група:</td><td>42</td><td>Поток:</td><td>8</td></tr>
<tr><td>Имейл в ТУ - София:</td><td>ivan@tu-sofia.bg<br><font size=1>Първоначалната парола за достъп е вашият ЕГН</font></td><td>Вид обучение:</td><td>редовно</td></tr>
</table>
<form name=nav action="index.php"><input type=hidden name=sid value=abc></form>
</body></html>
"""

GRADES_PAGE = """
<table>
<tr><th>Дисциплина</th><th>Лекции</th></tr>
<tr><td>1 сем. Математика 1 (изпит) Добър (4) (редовна) Отличен (6) (поправителна)</td></tr>
<tr><td>Програмиране (изпит) Мн. добър (5) (редовна)</td></tr>
<tr><td>Програмиране (курсов проект) Отличен (6) (редовна)</td></tr>
<tr><td>Физическо възпитание (текуща оценка) Зачита се</td></tr>
<tr><td>2 сем. Математика 2 (изпит) Слаб (2) (редовна)</td></tr>
<tr><td>Английски език (изпит)</td></tr>
<tr><td>Математика 2 (изпит) Среден (3) (поправителна)</td></tr>
</table>
"""


def soup(markup: str) -> BeautifulSoup:
    return BeautifulSoup(markup, "lxml")


def test_student_profile_is_normalized():
    page = soup(HOME_PAGE)
    student = parsers.build_student(parsers.parse_student_name(page), "000", parsers.parse_info(page))
    assert student.name == "Иван Петров Иванов"
    assert student.faculty_no == "121221089"
    assert student.ean == "AB12345"
    assert student.details["ЕАН"] == "AB12345"
    assert student.faculty == "Факултет Компютърни системи и технологии"
    assert student.specialty == "Компютърно и софтуерно инженерство"
    assert student.semester == 3
    assert student.course == 2
    assert student.group == "42"
    assert student.stream == "8"
    assert student.email == "ivan@tu-sofia.bg"
    assert student.details["Имейл в ТУ - София"] == "ivan@tu-sofia.bg"
    assert student.education_form == "редовно"


def test_grades_are_grouped_merged_and_sorted():
    grades = parsers.build_grades(parsers.parse_grade_rows(soup(GRADES_PAGE)))
    assert [semester.number for semester in grades.semesters] == [2, 1]

    second, first = grades.semesters
    math_two = next(subject for subject in second.subjects if subject.name == "Математика 2")
    assert math_two.grade == 3
    assert [attempt.kind for attempt in math_two.attempts] == ["regular", "retake"]
    assert any(subject.name == "Английски език" and subject.grade is None for subject in second.subjects)

    math_one = next(subject for subject in first.subjects if subject.name == "Математика 1")
    assert math_one.grade == 6
    assert math_one.label == "Отличен"

    programming = [subject for subject in first.subjects if subject.name == "Програмиране"]
    assert {subject.control for subject in programming} == {"изпит", "курсов проект"}

    sport = next(subject for subject in first.subjects if subject.name == "Физическо възпитание")
    assert sport.credited and sport.grade is None

    assert grades.graded_count == 4
    assert grades.credited_count == 1
    assert grades.gpa == 5.0
    assert first.average == 5.67
    assert grades.distribution == {"6": 2, "5": 1, "4": 0, "3": 1, "2": 0}


def test_legacy_rows_keep_v1_shape():
    rows = parsers.legacy_grade_rows(parsers.parse_grade_rows(soup(GRADES_PAGE)))
    assert rows[0] == {"is_semester": True, "title": "1 сем."}
    math_one = rows[1]
    assert math_one["regular"] == "Добър (4)"
    assert math_one["retake"] == "Отличен (6)"
    assert math_one["final"] == "Отличен (6)"
    sport = next(row for row in rows if row.get("subject") == "Физическо възпитание")
    assert sport["final"] == "Зачита се"


def test_dormitory_status():
    page = soup("<h3>Настаняване в общежития</h3><p>Вие сте настанен в блок 61, стая 402.</p>")
    dormitory = parsers.parse_dormitory(page)
    assert dormitory.accommodated
    assert "блок 61" in dormitory.status

    page = soup("<h3>Настаняване в общежития</h3><p>Не е настанен в общежитие.</p>")
    assert not parsers.parse_dormitory(page).accommodated


def test_failure_reason():
    page = soup("<font color=red>Грешен текст от изображението!</font>")
    assert "изображението" in parsers.parse_failure_reason(page)


def test_real_grades_table_layout():
    from pathlib import Path

    page = soup((Path(__file__).parent / "fixtures" / "grades_table.html").read_text(encoding="utf-8"))
    grades = parsers.build_grades(parsers.parse_grade_rows(page))
    assert [semester.number for semester in grades.semesters] == [3, 2, 1]
    assert grades.semesters[0].current
    assert not grades.semesters[1].current

    second = {subject.name: subject for subject in grades.semesters[1].subjects}
    modeling = second["Математическо моделиране и диференциални уравнения"]
    assert modeling.grade == 4
    assert [(attempt.kind, attempt.grade, attempt.date) for attempt in modeling.attempts] == [
        ("regular", 2, "2026-05-27"),
        ("retake", 4, "2026-06-18"),
    ]
    assert second["Приложна информатика"].grade == 5
    assert second["Спорт"].credited and second["Спорт"].control is None

    first = {subject.name: subject for subject in grades.semesters[2].subjects}
    analysis = first["Математически и матричен анализ"]
    assert analysis.grade == 3 and len(analysis.attempts) == 1
    assert first["Обектно-ориентирано програмиране-проект"].control == "Курсов проект"

    assert all(subject.grade is None for subject in grades.semesters[0].subjects)
    assert grades.gpa == 5.0
    assert grades.graded_count == 10
    assert grades.credited_count == 3

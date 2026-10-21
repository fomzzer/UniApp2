from enum import Enum
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field
from pydantic.alias_generators import to_camel


class APIModel(BaseModel):
    model_config = ConfigDict(alias_generator=to_camel, populate_by_name=True)


class LoginMethod(str, Enum):
    egn = "egn"
    otp = "otp"
    password = "password"


class MethodResponse(APIModel):
    method: LoginMethod


class LoginRequest(APIModel):
    faculty_no: str = Field(min_length=3, max_length=16, pattern=r"^\d+$")
    secret: str = Field(min_length=1, max_length=128)


class Student(APIModel):
    name: str
    faculty_no: str
    faculty: str | None = None
    specialty: str | None = None
    degree: str | None = None
    education_form: str | None = None
    semester: int | None = None
    course: int | None = None
    group: str | None = None
    stream: str | None = None
    email: str | None = None
    ean: str | None = None
    details: dict[str, str] = Field(default_factory=dict)


class Attempt(APIModel):
    kind: Literal["regular", "retake"]
    grade: int
    label: str
    date: str | None = None


class Subject(APIModel):
    name: str
    control: str | None = None
    grade: int | None = None
    label: str | None = None
    credited: bool = False
    attempts: list[Attempt] = Field(default_factory=list)


class Semester(APIModel):
    number: int | None = None
    title: str
    current: bool = False
    average: float | None = None
    subjects: list[Subject] = Field(default_factory=list)


class Grades(APIModel):
    gpa: float | None = None
    graded_count: int = 0
    credited_count: int = 0
    distribution: dict[str, int] = Field(default_factory=dict)
    semesters: list[Semester] = Field(default_factory=list)


class Dormitory(APIModel):
    status: str | None = None
    accommodated: bool = False


class Snapshot(APIModel):
    student: Student
    grades: Grades
    dormitory: Dormitory
    login_method: LoginMethod | None = None
    fetched_at: str


ScheduleKind = Literal["lectures", "exams"]


class ScheduleItem(APIModel):
    id: int
    kind: ScheduleKind
    academic_year: str | None = None
    semester: str | None = None
    degree: str
    faculty: str
    faculty_slug: str
    major: str
    major_slug: str
    year: int | None = None
    stream: str | None = None
    url: str
    is_pdf: bool


class ScheduleList(APIModel):
    updated_at: str | None = None
    items: list[ScheduleItem] = Field(default_factory=list)


class ErrorDetail(APIModel):
    code: str
    message: str


class ErrorResponse(APIModel):
    error: ErrorDetail


class Health(APIModel):
    status: str
    version: str
    schedules_updated_at: str | None = None

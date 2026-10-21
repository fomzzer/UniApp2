import pytest
from fastapi.testclient import TestClient

from app import errors, main
from app.etus import parsers
from app.etus.portal import PortalResult
from app.models import Dormitory, LoginMethod, ScheduleItem, ScheduleList
from app.ratelimit import SlidingWindowLimiter
from tests.test_parsers import GRADES_PAGE, HOME_PAGE, soup


@pytest.fixture
def client(monkeypatch):
    page = soup(HOME_PAGE)
    result = PortalResult(
        method=LoginMethod.egn,
        name=parsers.parse_student_name(page),
        info=parsers.parse_info(page),
        semesters=parsers.parse_grade_rows(soup(GRADES_PAGE)),
        dormitory=Dormitory(status="Настанен", accommodated=True),
    )

    def fake_fetch(faculty_no, secret):
        if secret != "good":
            raise errors.invalid_credentials()
        return result

    item = ScheduleItem(
        id=1, kind="lectures", degree="bachelor", faculty="F", faculty_slug="f", major="M",
        major_slug="m", year=2, stream="8", url="https://x/a.pdf", is_pdf=True,
    )
    monkeypatch.setattr(main.portal, "fetch", fake_fetch)
    monkeypatch.setattr(main.portal, "detect_method", lambda faculty_no: LoginMethod.password)
    monkeypatch.setattr(main.schedules, "get", lambda kind: ScheduleList(updated_at="2026-10-21T00:00:00Z", items=[item]))
    monkeypatch.setattr(main.schedules, "refresh_in_background", lambda: None)
    monkeypatch.setattr(main.portal.solver, "warm_up", lambda: None)
    monkeypatch.setattr(main, "ip_limiter", SlidingWindowLimiter(100, 60))
    monkeypatch.setattr(main, "student_limiter", SlidingWindowLimiter(3, 60))
    with TestClient(main.app) as test_client:
        yield test_client


def test_login_returns_camel_case_snapshot(client):
    response = client.post("/v2/auth/login", json={"facultyNo": "121221089", "secret": "good"})
    assert response.status_code == 200
    body = response.json()
    assert body["student"]["facultyNo"] == "121221089"
    assert body["student"]["course"] == 2
    assert body["grades"]["gradedCount"] == 4
    assert body["loginMethod"] == "egn"
    assert body["fetchedAt"].endswith("Z")


def test_login_errors_are_typed(client):
    response = client.post("/v2/auth/login", json={"facultyNo": "121221089", "secret": "bad"})
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "invalid_credentials"


def test_login_is_rate_limited_per_student(client):
    for _ in range(3):
        client.post("/v2/auth/login", json={"facultyNo": "555", "secret": "bad"})
    response = client.post("/v2/auth/login", json={"facultyNo": "555", "secret": "bad"})
    assert response.status_code == 429
    assert response.json()["error"]["code"] == "rate_limited"


def test_validation_error_shape(client):
    response = client.post("/v2/auth/login", json={"facultyNo": "abc", "secret": ""})
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


def test_method_endpoint(client):
    response = client.get("/v2/auth/method", params={"facultyNo": "121221089"})
    assert response.json() == {"method": "password"}


def test_schedules_endpoint(client):
    body = client.get("/v2/schedules", params={"kind": "lectures"}).json()
    assert body["items"][0]["majorSlug"] == "m"
    assert body["items"][0]["isPdf"] is True


def test_legacy_endpoints(client):
    body = client.post("/api/login", json={"faculty_no": "121221089", "auth_code": "good"}).json()
    assert body["status"] == "success"
    assert body["info"]["Поток"] == "8"
    assert client.get("/api/schedules").json()[0]["speciality"] == "M"


def test_legacy_login_rejects_malformed_input(client):
    assert client.post("/api/login", json={"faculty_no": "../etc", "auth_code": "good"}).status_code == 422
    assert client.post("/api/login", json={"faculty_no": "121221089", "auth_code": "x" * 500}).status_code == 422

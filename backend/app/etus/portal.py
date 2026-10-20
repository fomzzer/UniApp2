import hashlib
import logging
import re
import threading
import time
from dataclasses import dataclass
from urllib.parse import urljoin

import httpx
from bs4 import BeautifulSoup

from .. import errors
from ..config import Settings
from ..models import Dormitory, LoginMethod
from . import parsers

logger = logging.getLogger("uniapp.portal")

CAPTCHA_LENGTH = 6
CAPTCHA_SUBSTITUTIONS = str.maketrans({"0": "O", "1": "I", "2": "Z", "5": "S", "6": "G", "8": "B"})
LOCK_MARKERS = ("достъпът ще ви бъде отказан", "грешни опита", "блокиран")
CAPTCHA_MARKERS = ("изображ", "captcha", "символ", "код")
METHOD_CODES = {1: LoginMethod.egn, 2: LoginMethod.otp, 3: LoginMethod.password}


@dataclass
class PortalResult:
    method: LoginMethod
    name: str
    info: dict[str, str]
    semesters: list[parsers.SemesterRows]
    dormitory: Dormitory


class CaptchaSolver:
    def __init__(self) -> None:
        self._ocr = None
        self._lock = threading.Lock()

    def _engine(self):
        if self._ocr is None:
            import ddddocr

            try:
                self._ocr = ddddocr.DdddOcr(show_ad=False)
            except TypeError:
                self._ocr = ddddocr.DdddOcr()
        return self._ocr

    def solve(self, image: bytes) -> str:
        with self._lock:
            raw = self._engine().classification(image)
        normalized = str(raw).upper().translate(CAPTCHA_SUBSTITUTIONS)
        return re.sub(r"[^A-Z]", "", normalized)

    def warm_up(self) -> None:
        with self._lock:
            self._engine()


class PortalClient:
    def __init__(self, settings: Settings, solver: CaptchaSolver | None = None) -> None:
        self.settings = settings
        self.solver = solver or CaptchaSolver()
        self.base = settings.portal_url
        self.headers = {
            "User-Agent": settings.user_agent,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "bg-BG,bg;q=0.9,en;q=0.7",
            "Referer": settings.portal_url,
            "Origin": "https://e-university.tu-sofia.bg",
        }

    def _client(self) -> httpx.Client:
        return httpx.Client(headers=self.headers, timeout=self.settings.request_timeout, follow_redirects=True)

    @staticmethod
    def _soup(response: httpx.Response) -> BeautifulSoup:
        response.encoding = response.encoding or "utf-8"
        return BeautifulSoup(response.text, "lxml")

    def _open(self, client: httpx.Client) -> None:
        response = client.get(self.base)
        if response.status_code >= 500:
            raise errors.portal_unavailable(f"Portal responded with {response.status_code}")

    def _detect(self, client: httpx.Client, faculty_no: str) -> LoginMethod:
        response = client.get(urljoin(self.base, "prov-fn-ajax.php"), params={"fn": faculty_no})
        match = re.search(r"-?\d+", response.text or "")
        code = int(match.group()) if match else None
        if code == -1:
            raise errors.unknown_student()
        if code in METHOD_CODES:
            return METHOD_CODES[code]
        raise errors.portal_unavailable("Could not determine the login method")

    def detect_method(self, faculty_no: str) -> LoginMethod:
        try:
            with self._client() as client:
                self._open(client)
                return self._detect(client, faculty_no)
        except httpx.HTTPError as error:
            raise errors.portal_unavailable(str(error)) from error

    def _read_captcha(self, client: httpx.Client) -> str:
        for _ in range(self.settings.captcha_reads):
            response = client.get(urljoin(self.base, "captcha.php"), params={"r": str(time.time())})
            if response.status_code == 200 and response.content:
                text = self.solver.solve(response.content)
                if len(text) == CAPTCHA_LENGTH:
                    return text
            time.sleep(0.15)
        return ""

    def fetch(self, faculty_no: str, secret: str) -> PortalResult:
        try:
            return self._fetch(faculty_no, secret)
        except httpx.HTTPError as error:
            logger.warning("Portal transport failure: %s", error)
            raise errors.portal_unavailable(str(error)) from error

    def _fetch(self, faculty_no: str, secret: str) -> PortalResult:
        method: LoginMethod | None = None
        for attempt in range(1, self.settings.login_attempts + 1):
            with self._client() as client:
                self._open(client)
                method = self._detect(client, faculty_no)
                form = {"fnum": faculty_no}
                if method is LoginMethod.egn:
                    captcha = self._read_captcha(client)
                    if not captcha:
                        logger.info("Attempt %s: CAPTCHA unreadable", attempt)
                        continue
                    form["egn"] = secret
                    form["captcha"] = captcha
                elif method is LoginMethod.otp:
                    form["d_f_i"] = secret
                else:
                    form["parola"] = hashlib.md5(secret.encode("utf-8")).hexdigest()

                response = client.post(self.base, data=form)
                soup = self._soup(response)
                if soup.find("input", id="izh") is not None:
                    logger.info("Attempt %s: authenticated via %s", attempt, method.value)
                    return self._collect(client, soup, faculty_no, method)

                reason = parsers.parse_failure_reason(soup)
                lowered = reason.lower()
                if any(marker in lowered for marker in LOCK_MARKERS):
                    raise errors.portal_locked(reason)
                if method is not LoginMethod.egn:
                    raise errors.invalid_credentials()
                if reason and not any(marker in lowered for marker in CAPTCHA_MARKERS):
                    raise errors.invalid_credentials()
                logger.info("Attempt %s: CAPTCHA rejected", attempt)
                time.sleep(0.4)
        raise errors.captcha_failed()

    def _navigation_form(self, soup: BeautifulSoup) -> tuple[str, dict[str, str]]:
        action = self.base
        fields: dict[str, str] = {}
        form = soup.find("form", attrs={"name": "nav"})
        inputs = form.find_all("input") if form is not None else soup.find_all("input", type="hidden")
        if form is not None and form.get("action"):
            action = urljoin(self.base, form.get("action"))
        for item in inputs:
            name = item.get("name") or item.get("id")
            if name:
                fields[name] = item.get("value", "")
        return action, fields

    def _section(self, client: httpx.Client, action: str, fields: dict[str, str], section: str) -> BeautifulSoup:
        payload = dict(fields)
        payload["deistvie"] = section
        return self._soup(client.post(action, data=payload))

    def _collect(self, client: httpx.Client, soup: BeautifulSoup, faculty_no: str, method: LoginMethod) -> PortalResult:
        name = parsers.parse_student_name(soup)
        info = parsers.parse_info(soup)
        action, fields = self._navigation_form(soup)
        semesters = parsers.parse_grade_rows(self._section(client, action, fields, "1"))
        try:
            dormitory = parsers.parse_dormitory(self._section(client, action, fields, "7"))
        except httpx.HTTPError as error:
            logger.warning("Dormitory section failed: %s", error)
            dormitory = Dormitory(status=None, accommodated=False)
        if not name and not info:
            raise errors.parse_failed()
        return PortalResult(method=method, name=name, info=info, semesters=semesters, dormitory=dormitory)

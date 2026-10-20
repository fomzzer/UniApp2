class ServiceError(Exception):
    def __init__(self, code: str, status: int, message: str):
        super().__init__(message)
        self.code = code
        self.status = status
        self.message = message


def invalid_credentials() -> ServiceError:
    return ServiceError("invalid_credentials", 401, "Invalid faculty number or secret")


def unknown_student() -> ServiceError:
    return ServiceError("unknown_student", 404, "Faculty number does not exist")


def rate_limited() -> ServiceError:
    return ServiceError("rate_limited", 429, "Too many login attempts, try again later")


def portal_locked(reason: str) -> ServiceError:
    return ServiceError("portal_locked", 423, reason or "The portal temporarily blocked this account")


def captcha_failed() -> ServiceError:
    return ServiceError("captcha_failed", 502, "Could not solve the portal CAPTCHA")


def portal_unavailable(detail: str = "") -> ServiceError:
    return ServiceError("portal_unavailable", 503, detail or "The university portal is unavailable")


def parse_failed() -> ServiceError:
    return ServiceError("parse_failed", 502, "The university portal returned an unexpected page")

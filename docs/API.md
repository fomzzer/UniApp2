# UniApp API v2

Base URL: `https://<DOMAIN>` (by default `https://20-215-255-122.sslip.io`).
All responses are JSON with **camelCase** keys. Dates are ISO 8601 UTC (`2026-10-21T09:30:00Z`).

## Errors

Every non-2xx response has the same shape:

```json
{ "error": { "code": "invalid_credentials", "message": "Invalid faculty number or secret" } }
```

| HTTP | code | Meaning |
|------|------|---------|
| 401 | `invalid_credentials` | Wrong EGN / one-time code / password |
| 404 | `unknown_student` | Faculty number does not exist |
| 422 | `validation_error` | Malformed request |
| 423 | `portal_locked` | E-Student temporarily blocked the account |
| 429 | `rate_limited` | Too many attempts (per IP and per faculty number) |
| 502 | `captcha_failed` | CAPTCHA could not be solved in all attempts |
| 502 | `parse_failed` | E-Student returned an unexpected page |
| 503 | `portal_unavailable` | E-Student is down or unreachable |

Clients map `code` to a localized message; `message` is for logs only.

## `GET /health`

```json
{ "status": "ok", "version": "2.0.0", "schedulesUpdatedAt": "2026-10-21T09:00:00Z" }
```

## `GET /v2/auth/method?facultyNo=121221089`

Asks E-Student which login method this faculty number uses.

```json
{ "method": "egn" }
```

`egn` — EGN/LNCh + CAPTCHA (solved by the server), `otp` — one-time code, `password` — E-Student password.

## `POST /v2/auth/login`

```json
{ "facultyNo": "121221089", "secret": "…" }
```

`secret` is the EGN/LNCh, the one-time code or the password, depending on the method. The server detects the method itself, sends the data to E-Student and keeps nothing.

Response — `Snapshot`:

```json
{
  "student": {
    "name": "Иван Петров Иванов",
    "facultyNo": "121221089",
    "faculty": "Факултет Компютърни системи и технологии",
    "specialty": "Компютърно и софтуерно инженерство",
    "degree": null,
    "educationForm": "редовно",
    "semester": 3,
    "course": 2,
    "group": "42",
    "stream": "8",
    "email": "ivan@tu-sofia.bg",
    "details": { "Фак. номер": "121221089" }
  },
  "grades": {
    "gpa": 5.0,
    "gradedCount": 4,
    "creditedCount": 1,
    "distribution": { "6": 2, "5": 1, "4": 0, "3": 1, "2": 0 },
    "semesters": [
      {
        "number": 2,
        "title": "2 сем.",
        "average": 3.0,
        "subjects": [
          {
            "name": "Математика 2",
            "control": "изпит",
            "grade": 3,
            "label": "Среден",
            "credited": false,
            "attempts": [
              { "kind": "regular", "grade": 2, "label": "Слаб" },
              { "kind": "retake", "grade": 3, "label": "Среден" }
            ]
          }
        ]
      }
    ]
  },
  "dormitory": { "status": "Вие сте настанен в блок 61", "accommodated": true },
  "loginMethod": "egn",
  "fetchedAt": "2026-10-21T09:30:00Z"
}
```

Semesters are sorted newest first. `grade` is the final grade (retake wins over regular), `credited` marks "Зачита се" subjects without a numeric grade.

## `GET /v2/schedules?kind=lectures|exams`

Weekly lecture schedules or exam-session schedules, aggregated from the official `tu-sofia.bg` API for all faculties and both bachelor and master degrees. Cached on the server for 3 hours.

```json
{
  "updatedAt": "2026-10-21T09:00:00Z",
  "items": [
    {
      "id": 553,
      "kind": "lectures",
      "academicYear": "2026/2027",
      "semester": "winter",
      "degree": "bachelor",
      "faculty": "Факултет „Компютърни системи и технологии“",
      "facultySlug": "faculty-of-computer-systems-and-technologies",
      "major": "Компютърни науки и инженерство на английски език",
      "majorSlug": "kompiutierni-nauki-i-inzenerstvo",
      "year": 1,
      "stream": "1",
      "url": "https://d3v.cloud.tu-sofia.bg/storage/download/schedules/….pdf",
      "isPdf": true
    }
  ]
}
```

`isPdf: false` means `url` points to an external web page (e.g. FDIBA) and should be opened in a browser.

## Legacy

`POST /api/login` and `GET /api/schedules` keep the exact v1.0 response shape so the old Qt app keeps working during the migration. They are hidden from the OpenAPI schema and will be removed later.

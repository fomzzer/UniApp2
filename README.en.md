# UniApp 2.0

[![Русский](https://img.shields.io/badge/%D0%A0%D1%83%D1%81%D1%81%D0%BA%D0%B8%D0%B9-30363D)](README.md)
[![English](https://img.shields.io/badge/English-0A84FF)](README.en.md)
[![Български](https://img.shields.io/badge/%D0%91%D1%8A%D0%BB%D0%B3%D0%B0%D1%80%D1%81%D0%BA%D0%B8-30363D)](README.bg.md)

[![Download IPA](https://img.shields.io/github/v/release/fomzzer/UniApp2?label=download%20IPA&logo=apple&color=0A84FF)](https://github.com/fomzzer/UniApp2/releases/latest)
![iOS 18+](https://img.shields.io/badge/iOS-18%2B-black?logo=apple)
[![iOS](https://github.com/fomzzer/UniApp2/actions/workflows/ios.yml/badge.svg)](https://github.com/fomzzer/UniApp2/actions/workflows/ios.yml)

An unofficial "E-Student" client for students of the Technical University of Sofia: profile, grades, dormitory, class and exam schedules. A complete remake of version 1.0 (Qt/C++): a native SwiftUI iOS client with Liquid Glass and a new backend.

**Download:** a ready-made `.ipa` for iPhone (iOS 18+) and installation instructions are on the [latest release](https://github.com/fomzzer/UniApp2/releases/latest) page.

> Independent, non-commercial student project. Not affiliated with, endorsed by or connected to the Technical University of Sofia. The official university portals remain the authoritative source.

## Structure

```
UniApp2/
├── ios/                 SwiftUI app (iOS 18+)
│   ├── project.yml      XcodeGen spec → UniApp.xcodeproj
│   ├── UniApp/          sources
│   ├── UniAppTests/     unit tests
│   └── MailIntegration/ mail sending check against a real Roundcube
├── backend/             FastAPI + Docker Compose + Caddy (HTTPS)
├── docs/API.md          API v2 contract (shared by iOS and the future Android app)
└── .github/workflows/   CI: .ipa builds, releases, backend tests, simulator recordings and screenshots
```

## iOS

- **SwiftUI, iOS 18+**. On iOS 26 it uses real Liquid Glass (`glassEffect`, `GlassEffectContainer`, `.glassProminent`); on iOS 18–25 the same design is built on translucent materials (`DesignSystem/Compat.swift`). Blue-black palette, dark theme.
- **Languages**: Bulgarian and Russian, switchable inside the app (defaults to the system language).
- **Sign-in**: the app asks the portal which sign-in method applies to the faculty number — EGN/LNCh (the server solves the captcha), one-time password or password.
- **Home** in the spirit of Revolut: the grade average as a "balance", a 2–6 scale, quick actions, a per-semester chart, my schedule, dormitory, latest grades.
- **Grades**: semesters, search, grade distribution, subject details with attempts (regular / resit).
- **Schedule**: your own class schedule is shown natively — "now" with lesson progress and "next", weekdays, odd/even week, group and subgroup selection, class type and room. When a PDF cannot be parsed, as well as for other groups' schedules and exams, the PDF opens inside the app with an offline cache. Automatic detection of "my" schedule from the profile, pinning, cascading filters.
- **Mail**: TUSmail inside the app — folders, unread, attachments, HTML messages in a dark palette; compose, reply, reply all, forward, flag, move, delete to Trash. Reading goes over IMAP, sending through the same server's Roundcube webmail (SMTP is closed from outside).
- **Security**: credentials are stored only in the Keychain (`WhenUnlockedThisDeviceOnly`), the on-disk snapshot uses `completeFileProtection`, Face ID lock, privacy cover in the app switcher.

### Build and CI

The Xcode project is not stored in the repository: it is generated from `ios/project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
cd ios && xcodegen generate && open UniApp.xcodeproj
```

The server address is set by the `UNIAPP_API_HOST` build setting in `ios/project.yml` (host only, the scheme is always `https`).

Building does not require a Mac: everything runs in GitHub Actions on macOS runners.

- **iOS** — on every change in `ios/` generates the project, runs the unit tests on a simulator and builds an unsigned `.ipa`.
- **Release** — builds a version and publishes it on the [Releases](https://github.com/fomzzer/UniApp2/releases) page together with installation instructions.
- **iOS capture** and **iOS screens** — video recordings of UI tests and screenshots of every screen with test data, with a choice of the simulator's iOS version.

The version, build number and short commit hash go into `Info.plist` and are shown in the app under "About".

## Backend

A FastAPI service that does not store personal data:

- `/v2/auth/method`, `/v2/auth/login` — sign-in to "E-Student" (three methods, smart captcha retries without risking an account lockout, rate limiting by IP and by faculty number), parsing of the profile, grades and dormitory;
- `/v2/schedules` — class and exam schedules from the official `tu-sofia.bg` JSON API, cached for 3 hours with background refresh and persistence to disk;
- `/v2/timetables/{id}` — a schedule PDF parsed into a list of classes: grid detection by lines, merged cells, diagonals as odd/even weeks, two-hour columns, several subjects in one cell. About 96% of published PDFs are parsed; the rest are marked `unsupported`. The start of the first teaching week is set by `UNIAPP_WEEK_ONE` (default `2026-09-14`); the week parity can be switched manually in the app;
- `/api/login`, `/api/schedules` — compatibility with the old version 1.0.

Details: [docs/API.md](docs/API.md).

### Running and tests

```bash
cd backend
python -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt
UNIAPP_DATA_DIR=./data python -m pytest -q
UNIAPP_DATA_DIR=./data uvicorn app.main:app --reload
```

### Deployment

The server runs on an Azure virtual machine with Docker Compose: an `api` container with FastAPI behind [Caddy](https://caddyserver.com), which obtains and renews a Let's Encrypt certificate on its own. This requires open ports 80 and 443 and a domain pointing to the machine's IP. Settings come from `backend/.env` (template: `.env.example`), and `backend/deploy.sh` starts everything.

## Android

The API contract in `docs/API.md` is the common ground for a future Android client (Kotlin + Jetpack Compose). All business logic (parsing, normalization, average calculation, schedules) lives on the server, so the client only needs the UI.

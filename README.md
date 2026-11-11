# UniApp 2.0

[![Скачать IPA](https://img.shields.io/github/v/release/fomzzer/UniApp2?label=%D1%81%D0%BA%D0%B0%D1%87%D0%B0%D1%82%D1%8C%20IPA&logo=apple&color=0A84FF)](https://github.com/fomzzer/UniApp2/releases/latest)
![iOS 18+](https://img.shields.io/badge/iOS-18%2B-black?logo=apple)
[![iOS](https://github.com/fomzzer/UniApp2/actions/workflows/ios.yml/badge.svg)](https://github.com/fomzzer/UniApp2/actions/workflows/ios.yml)

Неофициальный клиент «Е-Студент» для студентов ТУ-София: профиль, оценки, общежитие, расписание занятий и сессии. Полный ремейк версии 1.0 (Qt/C++): нативный iOS-клиент на SwiftUI с Liquid Glass и новый бэкенд.

**Скачать:** готовый `.ipa` для iPhone (iOS 18+) и инструкция по установке — на странице [последнего релиза](https://github.com/fomzzer/UniApp2/releases/latest).

> Independent, non-commercial student project. Not affiliated with, endorsed by or connected to the Technical University of Sofia. The official university portals remain the authoritative source.

## Структура

```
UniApp2/
├── ios/                 SwiftUI-приложение (iOS 18+)
│   ├── project.yml      спецификация XcodeGen → UniApp.xcodeproj
│   ├── UniApp/          исходники
│   ├── UniAppTests/     юнит-тесты
│   └── MailIntegration/ проверка отправки почты против настоящего Roundcube
├── backend/             FastAPI + Docker Compose + Caddy (HTTPS)
├── docs/API.md          контракт API v2 (общий для iOS и будущего Android)
└── .github/workflows/   CI: сборка .ipa, релизы, тесты бэкенда, записи и скриншоты с симулятора
```

## iOS

- **SwiftUI, iOS 18+**. На iOS 26 — настоящий Liquid Glass (`glassEffect`, `GlassEffectContainer`, `.glassProminent`), на iOS 18–25 — тот же дизайн на полупрозрачных материалах (`DesignSystem/Compat.swift`). Сине-чёрная палитра, тёмная тема.
- **Языки**: български и русский, переключение прямо в приложении (по умолчанию — язык системы).
- **Вход**: приложение само узнаёт у портала способ входа по факультетному номеру — ЕГН/ЛНЧ (капчу решает сервер), одноразовый пароль или пароль.
- **Главная** в духе Revolut: средний балл как «баланс», шкала 2–6, быстрые действия, график по семестрам, моё расписание, общежитие, последние оценки.
- **Оценки**: семестры, поиск, распределение оценок, детали предмета с попытками (редовна / поправителна).
- **Расписание**: своё расписание занятий показывается нативно — «сейчас» с прогрессом пары и «далее», дни недели, чётная/нечётная неделя, выбор группы и подгруппы, тип занятия и аудитория. Если PDF не удалось разобрать, а также для чужих расписаний и сессии — PDF внутри приложения с офлайн-кэшем. Автоподбор «моего» расписания по профилю, закрепление своего, каскадные фильтры.
- **Почта**: TUSmail внутри приложения — папки, непрочитанные, вложения, HTML-письма в тёмной гамме; новое письмо, ответ, ответ всем, пересылка, флажок, перемещение, удаление в «Корзину». Чтение идёт по IMAP, отправка — через веб-почту Roundcube того же сервера (SMTP снаружи закрыт).
- **Безопасность**: данные для входа — только в Keychain (`WhenUnlockedThisDeviceOnly`), снапшот на диске с `completeFileProtection`, блокировка Face ID, шторка в переключателе приложений.

### Сборка и CI

Xcode-проект не хранится в репозитории: он генерируется из `ios/project.yml` с помощью [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
cd ios && xcodegen generate && open UniApp.xcodeproj
```

Адрес сервера задаётся build-настройкой `UNIAPP_API_HOST` в `ios/project.yml` (только хост, схема всегда `https`).

Сборка не требует Mac: всё выполняется в GitHub Actions на macOS-раннерах.

- **iOS** — на каждое изменение в `ios/` генерирует проект, прогоняет юнит-тесты на симуляторе и собирает неподписанный `.ipa`.
- **Release** — собирает версию и публикует её на странице [Releases](https://github.com/fomzzer/UniApp2/releases) вместе с инструкцией по установке.
- **iOS capture** и **iOS screens** — запись видео UI-тестов и скриншоты всех экранов на тестовых данных, с выбором версии iOS симулятора.

Версия, номер сборки и короткий хэш коммита попадают в `Info.plist` и видны в приложении в разделе «О приложении».

## Backend

FastAPI-сервис без хранения персональных данных:

- `/v2/auth/method`, `/v2/auth/login` — вход в «Е-Студент» (три способа, умные повторы капчи без риска блокировки аккаунта, rate-limit по IP и по факультетному номеру), разбор профиля, оценок и общежития;
- `/v2/schedules` — расписания занятий и сессии из официального JSON API `tu-sofia.bg`, кэш на 3 часа с фоновым обновлением и сохранением на диск;
- `/v2/timetables/{id}` — PDF расписания, разобранный в список занятий: сетка по линиям, объединённые ячейки, диагонали как чётная/нечётная неделя, двухчасовые столбцы, несколько дисциплин в одной клетке. Разбирается около 96% опубликованных PDF; остальные помечаются `unsupported`. Начало первой учебной недели задаётся `UNIAPP_WEEK_ONE` (по умолчанию `2026-09-14`), в приложении чётность можно поменять вручную;
- `/api/login`, `/api/schedules` — совместимость со старой версией 1.0.

Подробно: [docs/API.md](docs/API.md).

### Запуск и тесты

```bash
cd backend
python -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt
UNIAPP_DATA_DIR=./data python -m pytest -q
UNIAPP_DATA_DIR=./data uvicorn app.main:app --reload
```

### Развёртывание

Сервер работает на виртуальной машине Azure в Docker Compose: контейнер `api` с FastAPI и [Caddy](https://caddyserver.com) перед ним, который сам получает и продлевает сертификат Let's Encrypt. Для этого нужны открытые порты 80 и 443 и домен, указывающий на IP машины. Настройки берутся из `backend/.env` (шаблон — `.env.example`), запуск — `backend/deploy.sh`.

## Android

Контракт API в `docs/API.md` — общая точка для будущего Android-клиента (Kotlin + Jetpack Compose). Вся бизнес-логика (парсинг, нормализация, подсчёт среднего, расписания) живёт на сервере, поэтому клиенту остаётся только UI.

# UniApp 2.0

Неофициальный клиент «Е-Студент» для студентов ТУ-София: профиль, оценки, общежитие, расписание занятий и сессии. Полный ремейк версии 1.0 (Qt/C++): нативный iOS-клиент на SwiftUI с Liquid Glass и новый бэкенд.

> Independent, non-commercial student project. Not affiliated with, endorsed by or connected to the Technical University of Sofia. The official university portals remain the authoritative source.

## Структура

```
UniApp2/
├── ios/                 SwiftUI-приложение (iOS 26+)
│   ├── project.yml      спецификация XcodeGen → UniApp.xcodeproj
│   ├── UniApp/          исходники
│   └── UniAppTests/     юнит-тесты
├── backend/             FastAPI + Docker Compose + Caddy (HTTPS)
├── docs/API.md          контракт API v2 (общий для iOS и будущего Android)
└── .github/workflows/   CI: сборка .ipa и тесты бэкенда
```

## iOS

- **SwiftUI, iOS 26**, настоящий Liquid Glass (`glassEffect`, `GlassEffectContainer`, `.glassProminent`), сине-чёрная палитра, тёмная тема.
- **Языки**: български и русский, переключение прямо в приложении (по умолчанию — язык системы).
- **Вход**: приложение само узнаёт у портала способ входа по факультетному номеру — ЕГН/ЛНЧ (капчу решает сервер), одноразовый пароль или пароль.
- **Главная** в духе Revolut: средний балл как «баланс», шкала 2–6, быстрые действия, график по семестрам, моё расписание, общежитие, последние оценки.
- **Оценки**: семестры, поиск, распределение оценок, детали предмета с попытками (редовна / поправителна).
- **Расписание**: занятия и сессия, автоподбор «моего» расписания по профилю, закрепление своего, каскадные фильтры, PDF открывается внутри приложения и кэшируется офлайн.
- **Безопасность**: данные для входа — только в Keychain (`WhenUnlockedThisDeviceOnly`), снапшот на диске с `completeFileProtection`, блокировка Face ID, шторка в переключателе приложений.

### Сборка без Mac

Каждый пуш в `main`, который меняет `ios/`, запускает workflow **iOS** на macOS-раннере GitHub:

1. `xcodegen generate` создаёт проект,
2. прогоняются юнит-тесты на симуляторе,
3. собирается **неподписанный** `UniApp.ipa` и прикладывается к запуску как артефакт.

Версия берётся из номера запуска workflow: запуск №N даёт артефакт `UniApp-N-unsigned-ipa` с версией `2.0.N` и сборкой `N`.

Скачай артефакт в Actions → нужный запуск → `UniApp-…-unsigned-ipa`, распакуй и установи `UniApp.ipa` через **Sideloadly** (он подпишет своим Apple ID). Запустить вручную: Actions → iOS → *Run workflow*.

### Сборка на Mac

```bash
brew install xcodegen
cd ios && xcodegen generate && open UniApp.xcodeproj
```

Адрес сервера задаётся build-настройкой `UNIAPP_API_HOST` в `ios/project.yml` (только хост, схема всегда `https`).

## Backend

FastAPI-сервис без хранения персональных данных:

- `/v2/auth/method`, `/v2/auth/login` — вход в «Е-Студент» (три способа, умные повторы капчи без риска блокировки аккаунта, rate-limit по IP и по факультетному номеру), разбор профиля, оценок и общежития;
- `/v2/schedules` — расписания занятий и сессии из официального JSON API `tu-sofia.bg`, кэш на 3 часа с фоновым обновлением и сохранением на диск;
- `/api/login`, `/api/schedules` — совместимость со старой версией 1.0.

Подробно: [docs/API.md](docs/API.md).

### Локально

```bash
cd backend
python -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt
UNIAPP_DATA_DIR=./data python -m pytest -q
UNIAPP_DATA_DIR=./data uvicorn app.main:app --reload
```

### Деплой на Azure VM

Нужно: Docker с compose-плагином, открытые входящие порты **80** и **443** в Network Security Group виртуалки (для выпуска сертификата Let's Encrypt), и домен, указывающий на IP. Если своего домена нет, подойдёт `20-215-255-122.sslip.io` — он автоматически резолвится в этот IP.

```bash
cd backend
cp .env.example .env
./deploy.sh
```

`deploy.sh` поднимает `api` + `caddy`. Caddy сам получает и продлевает HTTPS-сертификат.

## Android

Контракт API в `docs/API.md` — общая точка для будущего Android-клиента (Kotlin + Jetpack Compose). Вся бизнес-логика (парсинг, нормализация, подсчёт среднего, расписания) живёт на сервере, поэтому клиенту остаётся только UI.

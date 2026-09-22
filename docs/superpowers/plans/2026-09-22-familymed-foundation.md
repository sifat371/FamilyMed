# FamilyMed Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a runnable, tested FamilyMed monorepo with a FastAPI/PostgreSQL backend foundation and a Flutter mobile shell that already uses the approved visual language, localization structure, routing, secure configuration, and local persistence boundary.

**Architecture:** This plan creates the shared foundation only. The backend exposes health/readiness endpoints and a tested database/config layer; the Flutter app boots into the FamilyMed shell with theme, localization, routing, and Drift database initialization. Product features such as authentication, family members, medication schedules, dose actions, prescription upload, and OCR are intentionally deferred to follow-up plans so this increment remains independently reviewable and testable.

**Tech Stack:** Flutter/Dart, FastAPI, Python 3.13, PostgreSQL 17, SQLAlchemy 2.x, Alembic, Pydantic Settings v2, pytest, httpx, Drift/SQLite, Riverpod, go_router, flutter_secure_storage, Docker Compose, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-22-familymed-v1-design.md`

## Global Constraints

- Family care is the product; prescription AI is an assistant inside it.
- Flutter is the mobile client; FastAPI is the backend; PostgreSQL is the server database.
- Mobile local state uses Drift/SQLite; authentication secrets use secure device storage.
- User-facing strings must be localization keys from the first Flutter commit; English and Bangla resources are required.
- All backend entity IDs use UUIDs.
- Database timestamps are UTC; user/member schedule display uses IANA timezones such as `Asia/Dhaka`.
- Prescription images are not stored in PostgreSQL.
- AI/OCR is not implemented in this plan.
- No V1 code may imply that an AI suggestion is a prescription decision or that a marked dose proves ingestion.
- Work occurs on a feature branch; `main` remains releasable.

## Review Focus

1. **Backend starts without PostgreSQL being ready:** `/health` should still report process liveness, while `/ready` must fail cleanly rather than crashing the process.
2. **Malformed or missing environment configuration:** production-like settings must reject an absent database URL/secret instead of silently using unsafe defaults.
3. **Bangla localization fallback:** switching to Bangla must render known translated strings and safely fall back for framework-level locale behavior without runtime exceptions.
4. **Fresh mobile install with no local database file:** Drift initialization must create/open the database successfully without requiring network access.
5. **CI on a clean runner:** backend tests, formatting/static checks, and Flutter analyze/test must work without undeclared local tooling or secrets.

---

## File Structure Locked by This Plan

```text
FamilyMed/
├── .github/
│   └── workflows/
│       └── ci.yml
├── .gitignore
├── .editorconfig
├── README.md
├── docker-compose.yml
├── .env.example
├── backend/
│   ├── pyproject.toml
│   ├── alembic.ini
│   ├── app/
│   │   ├── __init__.py
│   │   ├── main.py
│   │   ├── config.py
│   │   ├── db.py
│   │   └── api/
│   │       ├── __init__.py
│   │       └── health.py
│   ├── migrations/
│   │   ├── env.py
│   │   └── versions/
│   └── tests/
│       ├── conftest.py
│       ├── test_config.py
│       └── test_health.py
├── mobile/
│   ├── pubspec.yaml
│   ├── analysis_options.yaml
│   ├── l10n.yaml
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app/
│   │   │   ├── app.dart
│   │   │   └── router.dart
│   │   ├── core/
│   │   │   ├── database/
│   │   │   │   ├── app_database.dart
│   │   │   │   └── app_database.g.dart
│   │   │   ├── localization/
│   │   │   └── theme/
│   │   │       └── familymed_theme.dart
│   │   └── features/
│   │       └── welcome/
│   │           └── presentation/
│   │               └── welcome_screen.dart
│   ├── lib/l10n/
│   │   ├── app_en.arb
│   │   └── app_bn.arb
│   └── test/
│       ├── app_test.dart
│       └── core/database/app_database_test.dart
├── ai/
│   └── README.md
├── infra/
│   └── README.md
└── docs/
    └── superpowers/
```

---

### Task 1: Monorepo development environment

**Files:**
- Create: `.gitignore`
- Create: `.editorconfig`
- Create: `.env.example`
- Create: `docker-compose.yml`
- Create: `README.md`
- Create: `ai/README.md`
- Create: `infra/README.md`

**Interfaces:**
- Consumes: approved V1 architecture from the spec.
- Produces: documented local startup contract and PostgreSQL service at `localhost:5432` with database `familymed`.

- [ ] **Step 1: Create the feature branch**

Run:

```bash
git checkout -b feat/foundation
```

Expected: current branch is `feat/foundation`.

- [ ] **Step 2: Add repository-wide ignore and editor rules**

Create `.editorconfig`:

```ini
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
indent_style = space
indent_size = 2

[*.py]
indent_size = 4

[Makefile]
indent_style = tab
```

Create `.gitignore`:

```gitignore
.env
.env.*
!.env.example

# Python
__pycache__/
*.py[cod]
.pytest_cache/
.ruff_cache/
.venv/
backend/.coverage

# Flutter/Dart
mobile/.dart_tool/
mobile/build/
mobile/.flutter-plugins
mobile/.flutter-plugins-dependencies
mobile/coverage/

# IDE / OS
.idea/
.vscode/
.DS_Store

# Local data
*.sqlite
*.sqlite3
storage/
```

- [ ] **Step 3: Define development environment variables**

Create `.env.example`:

```dotenv
FAMILYMED_ENV=development
FAMILYMED_DATABASE_URL=postgresql+asyncpg://familymed:familymed@localhost:5432/familymed
FAMILYMED_JWT_SECRET=change-me-in-local-env
FAMILYMED_CORS_ORIGINS=http://localhost:3000
POSTGRES_DB=familymed
POSTGRES_USER=familymed
POSTGRES_PASSWORD=familymed
```

- [ ] **Step 4: Add PostgreSQL Docker service**

Create `docker-compose.yml`:

```yaml
services:
  postgres:
    image: postgres:17-alpine
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-familymed}
      POSTGRES_USER: ${POSTGRES_USER:-familymed}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-familymed}
    ports:
      - "5432:5432"
    volumes:
      - familymed_postgres:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-familymed} -d ${POSTGRES_DB:-familymed}"]
      interval: 5s
      timeout: 5s
      retries: 10

volumes:
  familymed_postgres:
```

- [ ] **Step 5: Add root documentation**

Create `README.md` with these exact development commands:

```markdown
# FamilyMed

FamilyMed is a family medication-care application. The mobile client is Flutter; the API is FastAPI/PostgreSQL. Prescription AI is an assistive subsystem and never activates medication without human confirmation.

## Repository

- `mobile/` — Flutter app
- `backend/` — FastAPI API
- `ai/` — prescription extraction service boundary; mocked before real OCR
- `infra/` — deployment/infrastructure notes
- `docs/` — architecture, design, and implementation plans

## Local database

```bash
cp .env.example .env
docker compose up -d postgres
```

## Backend

```bash
cd backend
uv sync --all-groups
uv run alembic upgrade head
uv run uvicorn app.main:app --reload
```

## Mobile

```bash
cd mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
flutter run
```

## Tests

```bash
cd backend && uv run pytest
cd mobile && flutter analyze && flutter test
```
```

Create `ai/README.md`:

```markdown
# AI service

The V1 product is developed against a mocked prescription-extraction contract first. Real OCR/HTR and pharmaceutical-lexicon retrieval are added only after the medication-care workflow is working. This service never creates active medications or schedules.
```

Create `infra/README.md`:

```markdown
# Infrastructure

Development uses Docker Compose for PostgreSQL. Production infrastructure will use private object storage for prescription images, PostgreSQL, HTTPS, and separately deployable backend/AI services.
```

- [ ] **Step 6: Smoke-test PostgreSQL**

Run:

```bash
cp .env.example .env
docker compose up -d postgres
docker compose ps
```

Expected: `postgres` reports `healthy`.

- [ ] **Step 7: Commit**

```bash
git add .editorconfig .gitignore .env.example docker-compose.yml README.md ai/README.md infra/README.md
git commit -m "chore: establish FamilyMed monorepo environment"
```

---

### Task 2: FastAPI configuration and liveness foundation

**Files:**
- Create: `backend/pyproject.toml`
- Create: `backend/app/__init__.py`
- Create: `backend/app/config.py`
- Create: `backend/app/main.py`
- Create: `backend/app/api/__init__.py`
- Create: `backend/app/api/health.py`
- Create: `backend/tests/test_config.py`
- Create: `backend/tests/test_health.py`

**Interfaces:**
- Consumes: `FAMILYMED_ENV`, `FAMILYMED_DATABASE_URL`, `FAMILYMED_JWT_SECRET`, `FAMILYMED_CORS_ORIGINS`.
- Produces: `Settings`, `get_settings()`, FastAPI `app`, `GET /api/v1/health`.

- [ ] **Step 1: Add backend package metadata and dependencies**

Create `backend/pyproject.toml`:

```toml
[project]
name = "familymed-backend"
version = "0.1.0"
description = "FamilyMed API"
requires-python = ">=3.13,<3.14"
dependencies = [
  "fastapi>=0.116,<1",
  "uvicorn[standard]>=0.35,<1",
  "sqlalchemy[asyncio]>=2.0,<3",
  "asyncpg>=0.30,<1",
  "alembic>=1.16,<2",
  "pydantic-settings>=2.10,<3",
]

[dependency-groups]
dev = [
  "httpx>=0.28,<1",
  "pytest>=8.4,<9",
  "pytest-asyncio>=1.1,<2",
  "ruff>=0.12,<1",
]

[tool.pytest.ini_options]
asyncio_mode = "auto"
testpaths = ["tests"]

[tool.ruff]
line-length = 100
target-version = "py313"

[tool.ruff.lint]
select = ["E", "F", "I", "B", "UP"]
```

- [ ] **Step 2: Write failing settings tests**

Create `backend/tests/test_config.py`:

```python
import pytest
from pydantic import ValidationError

from app.config import Settings


def test_settings_accept_explicit_development_values():
    settings = Settings(
        env="development",
        database_url="postgresql+asyncpg://u:p@localhost:5432/db",
        jwt_secret="secret",
        cors_origins="http://localhost:3000",
    )
    assert settings.env == "development"
    assert settings.cors_origin_list == ["http://localhost:3000"]


def test_non_development_rejects_default_jwt_secret():
    with pytest.raises(ValidationError):
        Settings(
            env="production",
            database_url="postgresql+asyncpg://u:p@db:5432/db",
            jwt_secret="change-me-in-local-env",
            cors_origins="https://familymed.example",
        )
```

- [ ] **Step 3: Run the tests and verify failure**

Run:

```bash
cd backend
uv sync --all-groups
uv run pytest tests/test_config.py -v
```

Expected: FAIL because `app.config` does not exist.

- [ ] **Step 4: Implement settings**

Create `backend/app/config.py`:

```python
from functools import lru_cache
from typing import Literal

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file="../.env",
        env_prefix="FAMILYMED_",
        extra="ignore",
    )

    env: Literal["development", "test", "staging", "production"] = "development"
    database_url: str = "postgresql+asyncpg://familymed:familymed@localhost:5432/familymed"
    jwt_secret: str = "change-me-in-local-env"
    cors_origins: str = "http://localhost:3000"

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]

    @model_validator(mode="after")
    def validate_secrets(self) -> "Settings":
        if self.env in {"staging", "production"} and self.jwt_secret == "change-me-in-local-env":
            raise ValueError("FAMILYMED_JWT_SECRET must be explicitly configured")
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
```

- [ ] **Step 5: Run config tests**

Run:

```bash
uv run pytest tests/test_config.py -v
```

Expected: 2 PASS.

- [ ] **Step 6: Write the failing liveness test**

Create `backend/tests/test_health.py`:

```python
from fastapi.testclient import TestClient

from app.main import app


def test_health_reports_process_liveness():
    response = TestClient(app).get("/api/v1/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "service": "familymed-api"}
```

- [ ] **Step 7: Run test and verify failure**

Run:

```bash
uv run pytest tests/test_health.py -v
```

Expected: FAIL because the route/app does not exist.

- [ ] **Step 8: Implement the FastAPI app and route**

Create `backend/app/api/health.py`:

```python
from fastapi import APIRouter

router = APIRouter(tags=["health"])


@router.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "service": "familymed-api"}
```

Create `backend/app/main.py`:

```python
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.health import router as health_router
from app.config import get_settings

settings = get_settings()

app = FastAPI(title="FamilyMed API", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.include_router(health_router, prefix="/api/v1")
```

Create empty package files `backend/app/__init__.py` and `backend/app/api/__init__.py`.

- [ ] **Step 9: Verify tests and lint**

Run:

```bash
uv run pytest -v
uv run ruff check .
```

Expected: all tests PASS; Ruff reports no errors.

- [ ] **Step 10: Commit**

```bash
git add backend
git commit -m "feat: add FastAPI configuration and health endpoint"
```

---

### Task 3: PostgreSQL async database and readiness endpoint

**Files:**
- Create: `backend/app/db.py`
- Modify: `backend/app/api/health.py`
- Create: `backend/tests/conftest.py`
- Modify: `backend/tests/test_health.py`
- Create: `backend/alembic.ini`
- Create: `backend/migrations/env.py`
- Create: `backend/migrations/versions/0001_bootstrap.py`

**Interfaces:**
- Consumes: `Settings.database_url`.
- Produces: `engine`, `async_session_factory`, `get_db_session()`, `GET /api/v1/ready`, Alembic migration baseline.

- [ ] **Step 1: Write readiness behavior tests**

Append to `backend/tests/test_health.py`:

```python
from unittest.mock import AsyncMock

from app.api import health as health_module


def test_ready_returns_200_when_database_responds(monkeypatch):
    monkeypatch.setattr(health_module, "database_is_ready", AsyncMock(return_value=True))
    response = TestClient(app).get("/api/v1/ready")
    assert response.status_code == 200
    assert response.json() == {"status": "ready"}


def test_ready_returns_503_when_database_is_unavailable(monkeypatch):
    monkeypatch.setattr(health_module, "database_is_ready", AsyncMock(return_value=False))
    response = TestClient(app).get("/api/v1/ready")
    assert response.status_code == 503
    assert response.json()["detail"] == "database unavailable"
```

- [ ] **Step 2: Run and verify failure**

Run:

```bash
cd backend
uv run pytest tests/test_health.py -v
```

Expected: FAIL because `/ready` and `database_is_ready` do not exist.

- [ ] **Step 3: Implement async database boundary**

Create `backend/app/db.py`:

```python
from collections.abc import AsyncIterator

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.config import get_settings

settings = get_settings()
engine = create_async_engine(settings.database_url, pool_pre_ping=True)
async_session_factory = async_sessionmaker(engine, expire_on_commit=False)


async def get_db_session() -> AsyncIterator[AsyncSession]:
    async with async_session_factory() as session:
        yield session


async def database_is_ready() -> bool:
    try:
        async with engine.connect() as connection:
            await connection.execute(text("SELECT 1"))
        return True
    except Exception:
        return False
```

- [ ] **Step 4: Add readiness route**

Replace `backend/app/api/health.py` with:

```python
from fastapi import APIRouter, HTTPException, status

from app.db import database_is_ready

router = APIRouter(tags=["health"])


@router.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "service": "familymed-api"}


@router.get("/ready")
async def ready() -> dict[str, str]:
    if not await database_is_ready():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="database unavailable",
        )
    return {"status": "ready"}
```

- [ ] **Step 5: Run readiness tests**

Run:

```bash
uv run pytest tests/test_health.py -v
```

Expected: all PASS.

- [ ] **Step 6: Add Alembic baseline**

Create `backend/alembic.ini` with `script_location = migrations` and logging defaults. Create `backend/migrations/env.py` importing `get_settings()` and configuring Alembic with `settings.database_url.replace("+asyncpg", "")` for migration connectivity. Create `backend/migrations/versions/0001_bootstrap.py` with revision `0001_bootstrap`, no domain tables yet, and reversible `upgrade()`/`downgrade()` functions that return without side effects.

- [ ] **Step 7: Verify migration against PostgreSQL**

Run:

```bash
docker compose up -d postgres
cd backend
uv run alembic upgrade head
uv run alembic current
```

Expected: current revision is `0001_bootstrap`.

- [ ] **Step 8: Run the complete backend check**

```bash
uv run pytest -v
uv run ruff check .
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add backend
git commit -m "feat: add PostgreSQL readiness and migration foundation"
```

---

### Task 4: Flutter application shell and FamilyMed theme

**Files:**
- Create via Flutter scaffold: `mobile/`
- Modify: `mobile/pubspec.yaml`
- Create: `mobile/lib/main.dart`
- Create: `mobile/lib/app/app.dart`
- Create: `mobile/lib/app/router.dart`
- Create: `mobile/lib/core/theme/familymed_theme.dart`
- Create: `mobile/lib/features/welcome/presentation/welcome_screen.dart`
- Create: `mobile/test/app_test.dart`

**Interfaces:**
- Consumes: approved V1.1 Figma visual language.
- Produces: `FamilyMedApp`, `appRouter`, `FamilyMedTheme.light`, route `/welcome`.

- [ ] **Step 1: Scaffold Flutter application**

Run from repository root:

```bash
flutter create --platforms=android,ios --org com.familymed --project-name familymed mobile
```

Expected: `mobile/` builds with the Flutter stable SDK.

- [ ] **Step 2: Add foundation packages**

In `mobile/pubspec.yaml`, add:

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  flutter_riverpod: ^3.0.0
  go_router: ^16.0.0
  drift: ^2.28.0
  sqlite3_flutter_libs: ^0.5.39
  path_provider: ^2.1.5
  path: ^1.9.1
  flutter_secure_storage: ^9.2.4
  intl: any

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
  drift_dev: ^2.28.0
  build_runner: ^2.7.0
```

Run:

```bash
cd mobile
flutter pub get
```

- [ ] **Step 3: Write failing app-shell test**

Replace `mobile/test/app_test.dart` with:

```dart
import 'package:familymed/app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('boots into the FamilyMed welcome screen', (tester) async {
    await tester.pumpWidget(const FamilyMedApp());
    await tester.pumpAndSettle();

    expect(find.text('FamilyMed'), findsOneWidget);
    expect(find.text('Medication care for the people you love.'), findsOneWidget);
    expect(find.byType(MaterialApp), findsNothing);
    expect(find.byType(MaterialApp), findsNothing); // Router app is MaterialApp.router.
  });
}
```

- [ ] **Step 4: Run test and verify failure**

Run:

```bash
flutter test test/app_test.dart
```

Expected: FAIL because `FamilyMedApp` does not exist.

- [ ] **Step 5: Implement visual tokens and theme**

Create `mobile/lib/core/theme/familymed_theme.dart`:

```dart
import 'package:flutter/material.dart';

abstract final class FamilyMedColors {
  static const appBackground = Color(0xFFFFF9F3);
  static const surface = Colors.white;
  static const primary = Color(0xFF176B63);
  static const primarySoft = Color(0xFFDDEFEA);
  static const textPrimary = Color(0xFF17302D);
  static const textSecondary = Color(0xFF667873);
  static const border = Color(0xFFE6DED5);
  static const success = Color(0xFF2E7D5B);
  static const successSoft = Color(0xFFE4F4EA);
  static const warning = Color(0xFFC7684E);
  static const warningSoft = Color(0xFFFCE9E2);
}

abstract final class FamilyMedTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: FamilyMedColors.primary,
      brightness: Brightness.light,
      surface: FamilyMedColors.surface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(
        primary: FamilyMedColors.primary,
        surface: FamilyMedColors.surface,
        error: FamilyMedColors.warning,
      ),
      scaffoldBackgroundColor: FamilyMedColors.appBackground,
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: FamilyMedColors.textPrimary),
        headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: FamilyMedColors.textPrimary),
        titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: FamilyMedColors.textPrimary),
        bodyMedium: TextStyle(fontSize: 15, height: 1.45, color: FamilyMedColors.textPrimary),
        labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Implement welcome route and app shell**

Create `mobile/lib/features/welcome/presentation/welcome_screen.dart` with a `Scaffold` using the approved copy:

```dart
import 'package:familymed/core/theme/familymed_theme.dart';
import 'package:flutter/material.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: FamilyMedColors.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.favorite, color: FamilyMedColors.primary, size: 32),
              ),
              const SizedBox(height: 24),
              Text('FamilyMed', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 18),
              Text(
                'Medication care for the people you love.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 16),
              const Text(
                'Scan prescriptions, build routines, and stay connected with your family’s medication care.',
                textAlign: TextAlign.center,
              ),
              const Spacer(flex: 2),
              FilledButton(onPressed: () {}, child: const Text('Get started')),
              const SizedBox(height: 16),
              const Text('AI assists. You always confirm.', textAlign: TextAlign.center),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
```

Create `mobile/lib/app/router.dart`:

```dart
import 'package:familymed/features/welcome/presentation/welcome_screen.dart';
import 'package:go_router/go_router.dart';

final appRouter = GoRouter(
  initialLocation: '/welcome',
  routes: [
    GoRoute(path: '/welcome', builder: (context, state) => const WelcomeScreen()),
  ],
);
```

Create `mobile/lib/app/app.dart`:

```dart
import 'package:familymed/app/router.dart';
import 'package:familymed/core/theme/familymed_theme.dart';
import 'package:flutter/material.dart';

class FamilyMedApp extends StatelessWidget {
  const FamilyMedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'FamilyMed',
      theme: FamilyMedTheme.light,
      routerConfig: appRouter,
    );
  }
}
```

Replace `mobile/lib/main.dart`:

```dart
import 'package:familymed/app/app.dart';
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FamilyMedApp());
}
```

- [ ] **Step 7: Correct the app test to assert router shell**

Replace the duplicate MaterialApp assertions with:

```dart
expect(find.text('Get started'), findsOneWidget);
expect(find.text('AI assists. You always confirm.'), findsOneWidget);
```

- [ ] **Step 8: Run Flutter tests and static analysis**

```bash
flutter analyze
flutter test
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add mobile
git commit -m "feat: add Flutter shell and FamilyMed theme"
```

---

### Task 5: English/Bangla localization foundation

**Files:**
- Create: `mobile/l10n.yaml`
- Create: `mobile/lib/l10n/app_en.arb`
- Create: `mobile/lib/l10n/app_bn.arb`
- Modify: `mobile/pubspec.yaml`
- Modify: `mobile/lib/app/app.dart`
- Modify: `mobile/lib/features/welcome/presentation/welcome_screen.dart`
- Modify: `mobile/test/app_test.dart`

**Interfaces:**
- Consumes: Flutter `AppLocalizations` generator.
- Produces: localization keys for all welcome-screen copy and supported locales `en`, `bn`.

- [ ] **Step 1: Enable generated localization**

Under `flutter:` in `mobile/pubspec.yaml`, add:

```yaml
  generate: true
```

Create `mobile/l10n.yaml`:

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
```

- [ ] **Step 2: Add English and Bangla resource files**

Create `mobile/lib/l10n/app_en.arb`:

```json
{
  "appName": "FamilyMed",
  "welcomeHeadline": "Medication care for the people you love.",
  "welcomeBody": "Scan prescriptions, build routines, and stay connected with your family's medication care.",
  "getStarted": "Get started",
  "aiConfirmationNote": "AI assists. You always confirm."
}
```

Create `mobile/lib/l10n/app_bn.arb`:

```json
{
  "appName": "FamilyMed",
  "welcomeHeadline": "আপনার প্রিয়জনের ওষুধের যত্ন।",
  "welcomeBody": "প্রেসক্রিপশন স্ক্যান করুন, ওষুধের রুটিন গুছিয়ে নিন, এবং পরিবারের ওষুধের যত্নে সংযুক্ত থাকুন।",
  "getStarted": "শুরু করুন",
  "aiConfirmationNote": "AI সহায়তা করে। নিশ্চিত করেন আপনি।"
}
```

- [ ] **Step 3: Write localization widget tests**

Update `mobile/test/app_test.dart` so it includes:

```dart
import 'package:flutter/material.dart';

// Existing English test remains.

testWidgets('renders Bangla welcome copy', (tester) async {
  await tester.pumpWidget(const FamilyMedApp(locale: Locale('bn')));
  await tester.pumpAndSettle();

  expect(find.text('আপনার প্রিয়জনের ওষুধের যত্ন।'), findsOneWidget);
  expect(find.text('শুরু করুন'), findsOneWidget);
});
```

This requires `FamilyMedApp` to accept `Locale? locale`.

- [ ] **Step 4: Run test and verify failure**

```bash
flutter gen-l10n
flutter test test/app_test.dart
```

Expected: FAIL because the app/welcome screen still uses hard-coded strings and has no locale parameter.

- [ ] **Step 5: Wire AppLocalizations into the app**

Modify `FamilyMedApp` constructor to accept `this.locale`, add `locale`, `AppLocalizations.localizationsDelegates`, and `AppLocalizations.supportedLocales` to `MaterialApp.router`.

Replace every user-facing welcome string with values from:

```dart
final l10n = AppLocalizations.of(context)!;
```

Use `l10n.appName`, `l10n.welcomeHeadline`, `l10n.welcomeBody`, `l10n.getStarted`, and `l10n.aiConfirmationNote`.

- [ ] **Step 6: Verify localization and analysis**

```bash
flutter gen-l10n
flutter analyze
flutter test
```

Expected: PASS including Bangla test.

- [ ] **Step 7: Commit**

```bash
git add mobile
git commit -m "feat: add English and Bangla localization foundation"
```

---

### Task 6: Drift local database boundary

**Files:**
- Create: `mobile/lib/core/database/app_database.dart`
- Generate: `mobile/lib/core/database/app_database.g.dart`
- Create: `mobile/test/core/database/app_database_test.dart`

**Interfaces:**
- Consumes: Drift and SQLite.
- Produces: `AppDatabase`, schema version `1`, database initialization boundary suitable for later family/medication/dose tables.

- [ ] **Step 1: Write failing in-memory database test**

Create `mobile/test/core/database/app_database_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:familymed/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opens a fresh local database at schema version 1', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    expect(database.schemaVersion, 1);
    expect(await database.customSelect('SELECT 1 AS value').getSingle().then((row) => row.read<int>('value')), 1);
  });
}
```

- [ ] **Step 2: Run and verify failure**

```bash
flutter test test/core/database/app_database_test.dart
```

Expected: FAIL because `AppDatabase` does not exist.

- [ ] **Step 3: Implement the database boundary**

Create `mobile/lib/core/database/app_database.dart`:

```dart
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    return NativeDatabase(File(p.join(directory.path, 'familymed.sqlite')));
  });
}
```

- [ ] **Step 4: Generate Drift code**

Run:

```bash
dart run build_runner build --delete-conflicting-outputs
```

Expected: `app_database.g.dart` is created.

- [ ] **Step 5: Run database test and all Flutter checks**

```bash
flutter analyze
flutter test
```

Expected: PASS, including fresh in-memory initialization without network access.

- [ ] **Step 6: Commit**

```bash
git add mobile/lib/core/database mobile/test/core/database
git commit -m "feat: add Drift local database foundation"
```

---

### Task 7: Clean-run CI for backend and mobile

**Files:**
- Create: `.github/workflows/ci.yml`
- Modify: `README.md` only if actual CI commands differ from documented commands.

**Interfaces:**
- Consumes: backend and mobile commands defined in Tasks 1–6.
- Produces: required clean-run validation for Python lint/tests, PostgreSQL migration, Flutter analyze/tests.

- [ ] **Step 1: Add GitHub Actions workflow**

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  backend:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:17-alpine
        env:
          POSTGRES_DB: familymed
          POSTGRES_USER: familymed
          POSTGRES_PASSWORD: familymed
        ports:
          - 5432:5432
        options: >-
          --health-cmd "pg_isready -U familymed -d familymed"
          --health-interval 5s
          --health-timeout 5s
          --health-retries 10
    env:
      FAMILYMED_ENV: test
      FAMILYMED_DATABASE_URL: postgresql+asyncpg://familymed:familymed@localhost:5432/familymed
      FAMILYMED_JWT_SECRET: test-secret
      FAMILYMED_CORS_ORIGINS: http://localhost
    steps:
      - uses: actions/checkout@v4
      - uses: astral-sh/setup-uv@v6
        with:
          python-version: '3.13'
      - run: uv sync --all-groups
        working-directory: backend
      - run: uv run ruff check .
        working-directory: backend
      - run: uv run alembic upgrade head
        working-directory: backend
      - run: uv run pytest -v
        working-directory: backend

  mobile:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true
      - run: flutter pub get
        working-directory: mobile
      - run: flutter gen-l10n
        working-directory: mobile
      - run: dart run build_runner build --delete-conflicting-outputs
        working-directory: mobile
      - run: flutter analyze
        working-directory: mobile
      - run: flutter test
        working-directory: mobile
```

- [ ] **Step 2: Reproduce CI commands locally**

Run:

```bash
cd backend
uv sync --all-groups
uv run ruff check .
uv run alembic upgrade head
uv run pytest -v

cd ../mobile
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
```

Expected: every command exits `0`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml README.md
git commit -m "ci: validate backend and Flutter foundation"
```

- [ ] **Step 4: Push the feature branch and confirm CI**

```bash
git push -u origin feat/foundation
```

Expected: both `backend` and `mobile` GitHub Actions jobs pass.

---

## Foundation Completion Gate

This plan is complete only when all of the following are true:

```text
✓ `docker compose up -d postgres` reaches healthy state
✓ FastAPI `/api/v1/health` returns 200 without requiring a live DB query
✓ FastAPI `/api/v1/ready` returns 200 with DB available and 503 when unavailable
✓ Alembic reaches `0001_bootstrap` against PostgreSQL 17
✓ Flutter boots to the FamilyMed welcome screen
✓ FamilyMed colors/copy match the approved V1.1 direction
✓ English and Bangla localization tests pass
✓ Drift opens a fresh local database without network access
✓ backend Ruff + pytest pass
✓ Flutter analyze + tests pass
✓ GitHub Actions passes on a clean runner
```

## Follow-up Implementation Plans

After this foundation is merged, create and execute these plans in order:

1. `familymed-auth-family-medication.md` — email/password auth, family ownership, family-member profiles, medicine master/manual medication entry, medication schedules.
2. `familymed-doses-today-notifications.md` — rolling dose generation, Today aggregate, taken/snooze/skip/missed transitions, local notifications, history, offline sync queue.
3. `familymed-prescription-verification.md` — private prescription upload, mocked extraction contract, candidate selection vs explicit confirmation, prescription history.
4. `familymed-real-ocr-integration.md` — OCR/HTR, pharmaceutical lexicon retrieval/reranking, confidence/abstention, calibration and research evaluation without changing the app contract.

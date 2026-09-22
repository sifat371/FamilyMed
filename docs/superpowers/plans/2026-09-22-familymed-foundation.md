# FamilyMed Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a runnable, tested FamilyMed monorepo with a FastAPI/PostgreSQL backend foundation and a Flutter mobile shell using the approved visual language, localization structure, routing, and local persistence boundary.

**Architecture:** This plan creates the shared foundation only. The backend exposes liveness/readiness endpoints plus tested config/database boundaries; the Flutter app boots into the FamilyMed shell with theme, localization, routing, and Drift initialization. Authentication, family members, medicines, schedules, dose actions, prescriptions, and OCR are deliberately deferred to later plans so this increment is independently reviewable and testable.

**Tech Stack:** Flutter/Dart, FastAPI, Python 3.13, PostgreSQL 17, SQLAlchemy 2.x, Alembic, Pydantic Settings v2, pytest, httpx, Drift/SQLite, go_router, Docker Compose, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-22-familymed-v1-design.md`

## Global Constraints

- Family care is the product; prescription AI is an assistant inside it.
- Flutter is the mobile client; FastAPI is the backend; PostgreSQL is the server database.
- Mobile local state uses Drift/SQLite.
- User-facing strings must use localization keys from the first Flutter commit; English and Bangla resources are required.
- All backend entity IDs in later domain plans use UUIDs.
- Database timestamps are UTC; user/member schedule display uses IANA timezones such as `Asia/Dhaka`.
- Prescription images are not stored in PostgreSQL.
- AI/OCR is not implemented in this plan.
- No V1 code may imply that an AI suggestion is a prescription decision or that a marked dose proves ingestion.
- Work occurs on a feature branch; `main` remains releasable.

## Review Focus

1. **Backend starts while PostgreSQL is down:** `/health` stays 200; `/ready` returns 503 without crashing the app.
2. **Unsafe production configuration:** staging/production reject both the development JWT secret and development localhost database URL.
3. **Bangla localization:** a Bangla locale renders known translated welcome strings without runtime exceptions.
4. **Fresh mobile install:** Drift opens a brand-new local database without network access.
5. **Clean CI runner:** migrations, backend lint/tests, Flutter generation/analyze/tests run without undeclared secrets or local-only tools.

---

## File Structure Locked by This Plan

```text
FamilyMed/
├── .github/workflows/ci.yml
├── .editorconfig
├── .env.example
├── .gitignore
├── README.md
├── docker-compose.yml
├── backend/
│   ├── pyproject.toml
│   ├── alembic.ini
│   ├── app/
│   │   ├── __init__.py
│   │   ├── api/
│   │   │   ├── __init__.py
│   │   │   └── health.py
│   │   ├── config.py
│   │   ├── db.py
│   │   └── main.py
│   ├── migrations/
│   │   ├── env.py
│   │   ├── script.py.mako
│   │   └── versions/0001_bootstrap.py
│   └── tests/
│       ├── test_config.py
│       └── test_health.py
├── mobile/
│   ├── analysis_options.yaml
│   ├── l10n.yaml
│   ├── pubspec.yaml
│   ├── lib/
│   │   ├── app/app.dart
│   │   ├── app/router.dart
│   │   ├── core/database/app_database.dart
│   │   ├── core/database/app_database.g.dart
│   │   ├── core/theme/familymed_theme.dart
│   │   ├── features/welcome/presentation/welcome_screen.dart
│   │   ├── l10n/app_bn.arb
│   │   ├── l10n/app_en.arb
│   │   └── main.dart
│   └── test/
│       ├── app_test.dart
│       └── core/database/app_database_test.dart
├── ai/README.md
└── infra/README.md
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
- Consumes: approved V1 architecture.
- Produces: local PostgreSQL at `localhost:5432`, DB/user/password `familymed`, plus documented startup commands.

- [ ] **Step 1: Create feature branch**

```bash
git checkout -b feat/foundation
```

Expected: `git branch --show-current` prints `feat/foundation`.

- [ ] **Step 2: Add editor and ignore rules**

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
```

Create `.gitignore`:

```gitignore
.env
.env.*
!.env.example
__pycache__/
*.py[cod]
.pytest_cache/
.ruff_cache/
.venv/
backend/.coverage
mobile/.dart_tool/
mobile/build/
mobile/.flutter-plugins
mobile/.flutter-plugins-dependencies
mobile/coverage/
.idea/
.vscode/
.DS_Store
*.sqlite
*.sqlite3
storage/
```

- [ ] **Step 3: Add development environment contract**

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

- [ ] **Step 4: Add root documentation**

Create `README.md`:

```markdown
# FamilyMed

FamilyMed is a family medication-care application. Flutter is the mobile client; FastAPI/PostgreSQL is the API stack. Prescription AI is assistive and never activates medication without human confirmation.

## Structure

- `mobile/` — Flutter app
- `backend/` — FastAPI API
- `ai/` — extraction-service boundary; mocked before real OCR
- `infra/` — infrastructure notes
- `docs/` — specs and implementation plans

## Local PostgreSQL

    cp .env.example .env
    docker compose up -d postgres

## Backend

    cd backend
    uv sync --all-groups
    uv run alembic upgrade head
    uv run uvicorn app.main:app --reload

## Mobile

    cd mobile
    flutter pub get
    flutter gen-l10n
    dart run build_runner build --delete-conflicting-outputs
    flutter run

## Checks

    cd backend && uv run ruff check . && uv run pytest
    cd mobile && flutter analyze && flutter test
```

Create `ai/README.md`:

```markdown
# AI service

V1 is developed against a mocked prescription-extraction contract first. Real OCR/HTR and medicine retrieval are integrated later without changing the app's human-confirmation boundary. The AI service never creates active medications or schedules.
```

Create `infra/README.md`:

```markdown
# Infrastructure

Development uses Docker Compose for PostgreSQL. Production will use HTTPS, PostgreSQL, private object storage for prescription images, and separately deployable backend/AI services.
```

- [ ] **Step 5: Smoke-test PostgreSQL**

```bash
cp .env.example .env
docker compose up -d postgres
docker compose ps
```

Expected: `postgres` reports `healthy`.

- [ ] **Step 6: Commit**

```bash
git add .editorconfig .gitignore .env.example docker-compose.yml README.md ai/README.md infra/README.md
git commit -m "chore: establish FamilyMed monorepo environment"
```

---

### Task 2: FastAPI configuration and liveness

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

- [ ] **Step 1: Add backend dependencies**

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
  "psycopg[binary]>=3.2,<4",
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

- [ ] **Step 2: Write failing configuration tests**

Create `backend/tests/test_config.py`:

```python
import pytest
from pydantic import ValidationError

from app.config import Settings

DEV_DB = "postgresql+asyncpg://familymed:familymed@localhost:5432/familymed"


def test_settings_accept_explicit_development_values():
    settings = Settings(
        env="development",
        database_url=DEV_DB,
        jwt_secret="secret",
        cors_origins="http://localhost:3000",
    )
    assert settings.env == "development"
    assert settings.cors_origin_list == ["http://localhost:3000"]


def test_production_rejects_development_secret():
    with pytest.raises(ValidationError):
        Settings(
            env="production",
            database_url="postgresql+asyncpg://u:p@db:5432/familymed",
            jwt_secret="change-me-in-local-env",
            cors_origins="https://familymed.example",
        )


def test_production_rejects_development_database_url():
    with pytest.raises(ValidationError):
        Settings(
            env="production",
            database_url=DEV_DB,
            jwt_secret="production-secret",
            cors_origins="https://familymed.example",
        )
```

- [ ] **Step 3: Verify configuration tests fail**

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

DEV_DATABASE_URL = "postgresql+asyncpg://familymed:familymed@localhost:5432/familymed"
DEV_JWT_SECRET = "change-me-in-local-env"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file="../.env",
        env_prefix="FAMILYMED_",
        extra="ignore",
    )

    env: Literal["development", "test", "staging", "production"] = "development"
    database_url: str = DEV_DATABASE_URL
    jwt_secret: str = DEV_JWT_SECRET
    cors_origins: str = "http://localhost:3000"

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]

    @model_validator(mode="after")
    def reject_development_values_outside_dev(self) -> "Settings":
        if self.env in {"staging", "production"}:
            if self.jwt_secret == DEV_JWT_SECRET:
                raise ValueError("FAMILYMED_JWT_SECRET must be explicitly configured")
            if self.database_url == DEV_DATABASE_URL:
                raise ValueError("FAMILYMED_DATABASE_URL must be explicitly configured")
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
```

- [ ] **Step 5: Verify configuration tests pass**

```bash
uv run pytest tests/test_config.py -v
```

Expected: 3 PASS.

- [ ] **Step 6: Write failing health test**

Create `backend/tests/test_health.py`:

```python
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health_reports_process_liveness():
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "service": "familymed-api"}
```

- [ ] **Step 7: Verify health test fails**

```bash
uv run pytest tests/test_health.py -v
```

Expected: FAIL because `app.main` does not exist.

- [ ] **Step 8: Implement FastAPI application**

Create empty `backend/app/__init__.py` and `backend/app/api/__init__.py`.

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

- [ ] **Step 9: Verify backend checks**

```bash
uv run pytest -v
uv run ruff check .
```

Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add backend
git commit -m "feat: add FastAPI configuration and liveness endpoint"
```

---

### Task 3: PostgreSQL readiness and Alembic baseline

**Files:**
- Create: `backend/app/db.py`
- Modify: `backend/app/api/health.py`
- Modify: `backend/tests/test_health.py`
- Create: `backend/alembic.ini`
- Create: `backend/migrations/env.py`
- Create: `backend/migrations/script.py.mako`
- Create: `backend/migrations/versions/0001_bootstrap.py`

**Interfaces:**
- Consumes: `Settings.database_url`.
- Produces: `engine`, `async_session_factory`, `get_db_session()`, `database_is_ready()`, `/api/v1/ready`, Alembic revision `0001_bootstrap`.

- [ ] **Step 1: Write failing readiness tests**

Append to `backend/tests/test_health.py`:

```python
from unittest.mock import AsyncMock

from app.api import health as health_module


def test_ready_returns_200_when_database_responds(monkeypatch):
    monkeypatch.setattr(health_module, "database_is_ready", AsyncMock(return_value=True))
    response = client.get("/api/v1/ready")
    assert response.status_code == 200
    assert response.json() == {"status": "ready"}


def test_ready_returns_503_when_database_is_unavailable(monkeypatch):
    monkeypatch.setattr(health_module, "database_is_ready", AsyncMock(return_value=False))
    response = client.get("/api/v1/ready")
    assert response.status_code == 503
    assert response.json()["detail"] == "database unavailable"
```

- [ ] **Step 2: Verify readiness tests fail**

```bash
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

- [ ] **Step 4: Implement readiness endpoint**

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

- [ ] **Step 5: Verify readiness tests pass**

```bash
uv run pytest tests/test_health.py -v
```

Expected: PASS.

- [ ] **Step 6: Add Alembic configuration**

Create `backend/alembic.ini`:

```ini
[alembic]
script_location = migrations
prepend_sys_path = .

[loggers]
keys = root,sqlalchemy,alembic

[handlers]
keys = console

[formatters]
keys = generic

[logger_root]
level = WARN
handlers = console
qualname =

[logger_sqlalchemy]
level = WARN
handlers =
qualname = sqlalchemy.engine

[logger_alembic]
level = INFO
handlers =
qualname = alembic

[handler_console]
class = StreamHandler
args = (sys.stderr,)
level = NOTSET
formatter = generic

[formatter_generic]
format = %(levelname)-5.5s [%(name)s] %(message)s
datefmt = %H:%M:%S
```

Create `backend/migrations/env.py`:

```python
from logging.config import fileConfig

from alembic import context
from sqlalchemy import engine_from_config, pool

from app.config import get_settings

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

settings = get_settings()
sync_url = settings.database_url.replace("+asyncpg", "+psycopg")
config.set_main_option("sqlalchemy.url", sync_url)
target_metadata = None


def run_migrations_offline() -> None:
    context.configure(
        url=sync_url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
```

Create `backend/migrations/script.py.mako`:

```mako
"""${message}

Revision ID: ${up_revision}
Revises: ${down_revision | comma,n}
Create Date: ${create_date}
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
${imports if imports else ""}

revision: str = ${repr(up_revision)}
down_revision: Union[str, None] = ${repr(down_revision)}
branch_labels: Union[str, Sequence[str], None] = ${repr(branch_labels)}
depends_on: Union[str, Sequence[str], None] = ${repr(depends_on)}


def upgrade() -> None:
    ${upgrades if upgrades else "pass"}


def downgrade() -> None:
    ${downgrades if downgrades else "pass"}
```

Create `backend/migrations/versions/0001_bootstrap.py`:

```python
"""bootstrap migration foundation"""

revision = "0001_bootstrap"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
```

- [ ] **Step 7: Verify migration on PostgreSQL 17**

```bash
cd ..
docker compose up -d postgres
cd backend
uv run alembic upgrade head
uv run alembic current
```

Expected: output includes `0001_bootstrap (head)`.

- [ ] **Step 8: Verify all backend checks**

```bash
uv run ruff check .
uv run pytest -v
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add backend
git commit -m "feat: add PostgreSQL readiness and migration foundation"
```

---

### Task 4: Flutter application shell and visual theme

**Files:**
- Create via scaffold: `mobile/`
- Modify: `mobile/pubspec.yaml`
- Create: `mobile/lib/main.dart`
- Create: `mobile/lib/app/app.dart`
- Create: `mobile/lib/app/router.dart`
- Create: `mobile/lib/core/theme/familymed_theme.dart`
- Create: `mobile/lib/features/welcome/presentation/welcome_screen.dart`
- Replace: `mobile/test/widget_test.dart` with `mobile/test/app_test.dart`

**Interfaces:**
- Consumes: approved V1.1 Figma visual language.
- Produces: `FamilyMedApp`, `appRouter`, `FamilyMedTheme.light`, `/welcome`.

- [ ] **Step 1: Scaffold Flutter app**

```bash
flutter create --platforms=android,ios --org com.familymed --project-name familymed mobile
```

Expected: `cd mobile && flutter test` succeeds against the generated starter before replacement.

- [ ] **Step 2: Add foundation dependencies**

Add to `mobile/pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
  go_router: ^16.0.0
  drift: ^2.28.0
  sqlite3_flutter_libs: ^0.5.39
  path_provider: ^2.1.5
  path: ^1.9.1
  intl: any

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
  drift_dev: ^2.28.0
  build_runner: ^2.7.0
```

Then run:

```bash
cd mobile
flutter pub get
```

- [ ] **Step 3: Write failing welcome-shell test**

Delete `mobile/test/widget_test.dart` and create `mobile/test/app_test.dart`:

```dart
import 'package:familymed/app/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('boots into the FamilyMed welcome screen', (tester) async {
    await tester.pumpWidget(const FamilyMedApp());
    await tester.pumpAndSettle();

    expect(find.text('FamilyMed'), findsOneWidget);
    expect(find.text('Medication care for the people you love.'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
  });
}
```

- [ ] **Step 4: Verify welcome test fails**

```bash
flutter test test/app_test.dart
```

Expected: FAIL because `FamilyMedApp` does not exist.

- [ ] **Step 5: Implement FamilyMed theme**

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
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: FamilyMedColors.appBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: FamilyMedColors.primary,
          brightness: Brightness.light,
          surface: FamilyMedColors.surface,
        ).copyWith(error: FamilyMedColors.warning),
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
```

- [ ] **Step 6: Implement router, welcome screen, and app shell**

Create `mobile/lib/features/welcome/presentation/welcome_screen.dart`:

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
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: FamilyMedColors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.favorite, color: FamilyMedColors.primary, size: 32),
                ),
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

- [ ] **Step 7: Verify Flutter shell**

```bash
flutter analyze
flutter test test/app_test.dart
```

Expected: PASS.

- [ ] **Step 8: Commit**

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
- Consumes: Flutter generated `AppLocalizations`.
- Produces: supported locales `en`, `bn`; all welcome-screen copy uses localization keys.

- [ ] **Step 1: Configure Flutter localization generation**

Under the existing `flutter:` section in `mobile/pubspec.yaml`, add:

```yaml
  generate: true
```

Create `mobile/l10n.yaml`:

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
```

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

- [ ] **Step 2: Add failing Bangla widget test**

Replace `mobile/test/app_test.dart` with:

```dart
import 'package:familymed/app/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders English welcome copy', (tester) async {
    await tester.pumpWidget(const FamilyMedApp(locale: Locale('en')));
    await tester.pumpAndSettle();
    expect(find.text('Medication care for the people you love.'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
  });

  testWidgets('renders Bangla welcome copy', (tester) async {
    await tester.pumpWidget(const FamilyMedApp(locale: Locale('bn')));
    await tester.pumpAndSettle();
    expect(find.text('আপনার প্রিয়জনের ওষুধের যত্ন।'), findsOneWidget);
    expect(find.text('শুরু করুন'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Generate localization and verify tests fail**

```bash
flutter gen-l10n
flutter test test/app_test.dart
```

Expected: FAIL because `FamilyMedApp` has no `locale` parameter and the welcome screen still uses hard-coded copy.

- [ ] **Step 4: Wire localization into app shell**

Replace `mobile/lib/app/app.dart` with:

```dart
import 'package:familymed/app/router.dart';
import 'package:familymed/core/theme/familymed_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class FamilyMedApp extends StatelessWidget {
  const FamilyMedApp({super.key, this.locale});

  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appName,
      theme: FamilyMedTheme.light,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: appRouter,
    );
  }
}
```

Replace `mobile/lib/features/welcome/presentation/welcome_screen.dart` with:

```dart
import 'package:familymed/core/theme/familymed_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: FamilyMedColors.primarySoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.favorite, color: FamilyMedColors.primary, size: 32),
                ),
              ),
              const SizedBox(height: 24),
              Text(l10n.appName, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 18),
              Text(l10n.welcomeHeadline, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 16),
              Text(l10n.welcomeBody, textAlign: TextAlign.center),
              const Spacer(flex: 2),
              FilledButton(onPressed: () {}, child: Text(l10n.getStarted)),
              const SizedBox(height: 16),
              Text(l10n.aiConfirmationNote, textAlign: TextAlign.center),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Verify localization**

```bash
flutter gen-l10n
flutter analyze
flutter test
```

Expected: PASS including English and Bangla tests.

- [ ] **Step 6: Commit**

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
- Consumes: Drift/SQLite.
- Produces: `AppDatabase`, schema version `1`, production file `familymed.sqlite`, in-memory testing constructor.

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
    final row = await database.customSelect('SELECT 1 AS value').getSingle();
    expect(row.read<int>('value'), 1);
  });
}
```

- [ ] **Step 2: Verify test fails**

```bash
flutter test test/core/database/app_database_test.dart
```

Expected: FAIL because `AppDatabase` does not exist.

- [ ] **Step 3: Implement Drift database boundary**

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

  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

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

```bash
dart run build_runner build --delete-conflicting-outputs
```

Expected: `mobile/lib/core/database/app_database.g.dart` is generated.

- [ ] **Step 5: Verify database and all Flutter checks**

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

### Task 7: Clean-run CI

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: Tasks 1–6 commands.
- Produces: clean backend and mobile validation on every pull request and pushes to `main`.

- [ ] **Step 1: Add CI workflow**

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

- [ ] **Step 2: Reproduce CI locally**

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

- [ ] **Step 3: Commit and push**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: validate backend and Flutter foundation"
git push -u origin feat/foundation
```

Expected: GitHub Actions jobs `backend` and `mobile` both pass.

---

## Foundation Completion Gate

```text
✓ PostgreSQL 17 reaches healthy state
✓ /api/v1/health returns 200 without a database query
✓ /api/v1/ready returns 200 with PostgreSQL available and 503 when unavailable
✓ staging/production reject development secret and DB URL
✓ Alembic reaches 0001_bootstrap
✓ Flutter boots to approved FamilyMed welcome shell
✓ English and Bangla localization tests pass
✓ Drift opens a fresh local database without network access
✓ Ruff + pytest pass
✓ Flutter analyze + tests pass
✓ GitHub Actions passes on a clean runner
```

## Follow-up Implementation Plans

After the foundation branch is merged, create and execute these plans in order:

1. `familymed-auth-family-medication.md` — email/password auth, family ownership, family-member profiles, medicine master/manual medication entry, medication schedules.
2. `familymed-doses-today-notifications.md` — rolling dose generation, Today aggregate, taken/snooze/skip/missed transitions, local notifications, history, offline sync queue.
3. `familymed-prescription-verification.md` — private prescription upload, mocked extraction contract, candidate selection vs explicit confirmation, prescription history.
4. `familymed-real-ocr-integration.md` — OCR/HTR, pharmaceutical lexicon retrieval/reranking, confidence/abstention, calibration, and research evaluation without changing the app contract.

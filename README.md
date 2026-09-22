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
    dart run build_runner build
    flutter run

The Android emulator default API URL is `http://10.0.2.2:8000/api/v1`. Override it for another host or device with a Dart define:

    flutter run --dart-define=FAMILYMED_API_BASE_URL=http://192.168.1.10:8000/api/v1

Use an address reachable from the device. Do not hard-code development hosts into application source.

## Checks

    cd backend && uv run ruff check . && uv run pytest
    cd mobile && flutter analyze && flutter test

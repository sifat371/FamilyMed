# FamilyMed Auth + Family + Manual Medication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the first real FamilyMed vertical slice: a user can register or log in, restore an authenticated session, add Amma as a family member, manually add a draft medicine, and later reload the persisted family/member/medicine data from the FastAPI/PostgreSQL backend.

**Architecture:** Extend the existing foundation without changing the monorepo boundaries. Backend work adds SQLAlchemy domain models, one Alembic migration, JWT/Argon2 authentication, strict membership-scoped family APIs, and membership-scoped manual medication APIs. Flutter adds Riverpod, Dio, secure token storage, authenticated routing, the approved family onboarding screens, a returning-user family list, family-member profile, and manual-medication form. Schedules, notifications, Today, prescriptions, OCR/HTR, and offline write synchronization remain out of scope.

**Tech Stack:** Python 3.13, FastAPI, PostgreSQL 17, SQLAlchemy 2.x, Alembic, Pydantic v2, PyJWT, pwdlib/Argon2, pytest, httpx; Flutter/Dart, Riverpod, Dio, flutter_secure_storage, go_router, Flutter localization, existing FamilyMed theme.

**Spec:** `docs/superpowers/specs/2026-09-23-auth-family-medications-design.md`

## Global Constraints

- Branch: `feat/auth-family-medications`; do not commit product code directly to `main`.
- Registration/login is email + password only for this slice.
- Name: trimmed, 1-120 characters. Email: syntactically valid, trimmed and lowercased. Password: 8-128 characters.
- Access JWT lifetime: 15 minutes. Refresh JWT lifetime: 30 days. JWTs contain `sub=<user UUID>` and `type=access|refresh`.
- Refresh returns a new access token only; the existing refresh token remains valid until expiry. Do not claim revocation or rotation.
- Passwords use Argon2 and never appear in API output or logs.
- Registration creates User + Family + active owner FamilyMembership atomically.
- Requests outside the authenticated user's accessible family return 404, not 403, to avoid leaking cross-family resource existence.
- Family-member language values are exactly `en` or `bn`; date of birth cannot be in the future; timezone must be a valid IANA zone. New Flutter members default to `Asia/Dhaka`.
- Manual medicines use `medicine_master_id = NULL`, are created with `status=draft`, require `start_date`, and reject `end_date < start_date`.
- `prescription_id` and `extraction_id` are nullable UUID columns without foreign keys in this migration because those target tables do not exist yet.
- No schedule, dose, reminder, Today, prescription upload, OCR/HTR, medicine-catalog import, caregiver invitation, or offline write-sync code in this plan.
- All new mobile copy is localized in both English and Bangla; no hard-coded user-facing strings in widgets.
- Use the existing FamilyMed teal/cream theme and minimum ~44-48 px primary touch targets.
- Backend CI remains PostgreSQL-backed; mobile CI must still pass generation, analyze, tests, and Android debug build.

## Review Focus

1. **Email normalization collisions:** ` User@Example.com ` and `user@example.com` must resolve to one account and the second registration must return 409.
2. **Wrong JWT type or expired session:** access tokens cannot refresh; refresh tokens cannot authorize protected endpoints; unrecoverable Flutter refresh failure clears secure tokens and returns to login.
3. **Cross-family UUID probing:** user A must receive 404 for user B's member/medication on read, list, create, and update paths.
4. **Invalid dates/timezones:** future DOB, invalid IANA timezone, and medication end date before start date must produce the standard validation envelope without raw framework errors.
5. **Concurrent mobile 401s:** simultaneous protected requests must share one in-flight refresh instead of issuing duplicate refresh calls or racing token writes.

---

## File Structure Locked by This Plan

```text
backend/
├── pyproject.toml
├── uv.lock
├── app/
│   ├── config.py
│   ├── db.py
│   ├── models.py
│   ├── main.py
│   ├── api/health.py
│   ├── common/
│   │   ├── __init__.py
│   │   ├── auth.py
│   │   └── errors.py
│   ├── users/
│   │   ├── __init__.py
│   │   └── models.py
│   ├── auth/
│   │   ├── __init__.py
│   │   ├── router.py
│   │   ├── schemas.py
│   │   ├── security.py
│   │   └── service.py
│   ├── families/
│   │   ├── __init__.py
│   │   ├── models.py
│   │   ├── repository.py
│   │   ├── router.py
│   │   ├── schemas.py
│   │   └── service.py
│   └── medications/
│       ├── __init__.py
│       ├── models.py
│       ├── repository.py
│       ├── router.py
│       ├── schemas.py
│       └── service.py
├── migrations/
│   ├── env.py
│   └── versions/0002_auth_family_medications.py
└── tests/
    ├── conftest.py
    ├── test_auth.py
    ├── test_family_members.py
    └── test_medications.py

mobile/
├── pubspec.yaml
├── pubspec.lock
├── lib/
│   ├── main.dart
│   ├── app/
│   │   ├── app.dart
│   │   └── router.dart
│   ├── core/
│   │   ├── api/
│   │   │   ├── api_client.dart
│   │   │   └── api_error.dart
│   │   ├── auth/
│   │   │   ├── auth_controller.dart
│   │   │   ├── auth_state.dart
│   │   │   ├── auth_tokens.dart
│   │   │   └── token_store.dart
│   │   └── storage/
│   │       └── secure_token_store.dart
│   ├── features/
│   │   ├── welcome/presentation/welcome_screen.dart
│   │   ├── auth/
│   │   │   ├── data/auth_repository.dart
│   │   │   ├── domain/current_user.dart
│   │   │   └── presentation/
│   │   │       ├── login_screen.dart
│   │   │       └── register_screen.dart
│   │   ├── family/
│   │   │   ├── data/family_repository.dart
│   │   │   ├── domain/family_member.dart
│   │   │   └── presentation/
│   │   │       ├── add_family_member_screen.dart
│   │   │       ├── family_list_screen.dart
│   │   │       ├── member_profile_screen.dart
│   │   │       └── who_do_you_care_for_screen.dart
│   │   └── medications/
│   │       ├── data/medication_repository.dart
│   │       ├── domain/member_medication.dart
│   │       └── presentation/add_manual_medication_screen.dart
│   └── l10n/
│       ├── app_en.arb
│       └── app_bn.arb
└── test/
    ├── app_test.dart
    ├── core/api/api_client_test.dart
    ├── core/auth/auth_controller_test.dart
    ├── features/auth/auth_flow_test.dart
    ├── features/family/family_flow_test.dart
    └── features/medications/manual_medication_flow_test.dart
```

---

### Task 1: Backend domain persistence and migration

**Files:**
- Modify: `backend/app/db.py`
- Create: `backend/app/models.py`
- Create: `backend/app/users/__init__.py`
- Create: `backend/app/users/models.py`
- Create: `backend/app/families/__init__.py`
- Create: `backend/app/families/models.py`
- Create: `backend/app/medications/__init__.py`
- Create: `backend/app/medications/models.py`
- Modify: `backend/migrations/env.py`
- Create: `backend/migrations/versions/0002_auth_family_medications.py`
- Create: `backend/tests/conftest.py`
- Test: `backend/tests/test_auth.py`

**Interfaces:**
- Consumes: existing `get_db_session()` and PostgreSQL CI service.
- Produces: `Base`, `User`, `Family`, `FamilyMembership`, `FamilyMember`, `MedicineMaster`, `MemberMedication`, plus migrated tables at revision `0002_auth_family_medications`.

- [ ] **Step 1: Write the failing persistence test**

Create `backend/tests/test_auth.py` with a database-level test that expects the new models to persist and their defaults to be correct:

```python
from sqlalchemy import select

from app.families.models import Family, FamilyMembership
from app.users.models import User


async def test_user_family_membership_models_persist(db_session):
    user = User(name="Sifat", email="sifat@example.com", password_hash="argon2-hash")
    db_session.add(user)
    await db_session.flush()

    family = Family(name="Sifat's family", created_by_user_id=user.id)
    db_session.add(family)
    await db_session.flush()

    membership = FamilyMembership(
        family_id=family.id,
        user_id=user.id,
        role="owner",
        status="active",
    )
    db_session.add(membership)
    await db_session.flush()

    saved = await db_session.scalar(select(User).where(User.id == user.id))
    assert saved is not None
    assert saved.email == "sifat@example.com"
    assert membership.role == "owner"
    assert membership.status == "active"
```

`backend/tests/conftest.py` must provide an `AsyncSession` bound to the PostgreSQL test database and isolate each test with a rollback/savepoint so service commits do not leak rows between tests.

- [ ] **Step 2: Run the test and verify RED**

```bash
cd backend
uv run pytest tests/test_auth.py::test_user_family_membership_models_persist -v
```

Expected: FAIL because `app.users.models` / `app.families.models` do not exist.

- [ ] **Step 3: Introduce the declarative base and exact model fields**

Modify `backend/app/db.py`:

```python
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass
```

Implement model UUID primary keys with `uuid.uuid4`, timezone-aware `created_at`/`updated_at`, and the spec fields. Representative declarations:

```python
class User(Base):
    __tablename__ = "users"

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    email: Mapped[str] = mapped_column(String(255), nullable=False, unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(Text, nullable=False)
    preferred_language: Mapped[str] = mapped_column(String(5), nullable=False, default="en")
    timezone: Mapped[str] = mapped_column(String(64), nullable=False, default="Asia/Dhaka")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=utc_now, onupdate=utc_now)
```

```python
class FamilyMembership(Base):
    __tablename__ = "family_memberships"
    __table_args__ = (UniqueConstraint("family_id", "user_id", name="uq_family_membership"),)
```

`MemberMedication` must include `prescription_id` and `extraction_id` as nullable UUID columns without foreign keys.

- [ ] **Step 4: Register metadata for Alembic**

Create `backend/app/models.py` importing every model module, then update `backend/migrations/env.py`:

```python
from app.db import Base
import app.models  # noqa: F401

target_metadata = Base.metadata
```

- [ ] **Step 5: Add the explicit migration**

Create `0002_auth_family_medications.py` with `down_revision = "0001_bootstrap"`. The upgrade must create tables in dependency order:

```text
users
families
family_memberships
family_members
medicine_master
member_medications
```

Add indexes for:

```text
users(email) unique
family_members(family_id)
family_memberships(user_id, status)
member_medications(family_member_id, status)
```

Downgrade drops them in reverse order.

- [ ] **Step 6: Run migration and test**

```bash
cd backend
uv run alembic downgrade base
uv run alembic upgrade head
uv run pytest tests/test_auth.py::test_user_family_membership_models_persist -v
```

Expected: migration succeeds from empty database and the test PASSes.

- [ ] **Step 7: Run backend lint**

```bash
uv run ruff check .
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add backend/app backend/migrations backend/tests/conftest.py backend/tests/test_auth.py
git commit -m "feat: add auth family medication persistence"
```

---

### Task 2: Backend authentication, standard errors, and session restore

**Files:**
- Modify: `backend/pyproject.toml`
- Modify generated: `backend/uv.lock`
- Modify: `backend/app/config.py`
- Create: `backend/app/common/__init__.py`
- Create: `backend/app/common/errors.py`
- Create: `backend/app/common/auth.py`
- Create: `backend/app/auth/__init__.py`
- Create: `backend/app/auth/security.py`
- Create: `backend/app/auth/schemas.py`
- Create: `backend/app/auth/service.py`
- Create: `backend/app/auth/router.py`
- Modify: `backend/app/main.py`
- Modify/Test: `backend/tests/test_auth.py`

**Interfaces:**
- Consumes: `User`, `Family`, `FamilyMembership`, `get_db_session()`.
- Produces: `hash_password()`, `verify_password()`, `create_access_token()`, `create_refresh_token()`, `decode_token()`, `get_current_user()`, and `/api/v1/auth/register|login|refresh|me`.

- [ ] **Step 1: Add failing authentication API tests**

Add tests covering normalization, duplicate registration, hashing, generic invalid credentials, token typing, refresh, and `/me`:

```python
async def test_register_normalizes_email_and_creates_family(client, db_session):
    response = await client.post(
        "/api/v1/auth/register",
        json={"name": " Sifat ", "email": " USER@Example.com ", "password": "password123"},
    )
    assert response.status_code == 201
    body = response.json()
    assert body["user"]["name"] == "Sifat"
    assert body["user"]["email"] == "user@example.com"
    assert body["access_token"]
    assert body["refresh_token"]


async def test_duplicate_normalized_email_returns_standard_409(client):
    payload = {"name": "Sifat", "email": "user@example.com", "password": "password123"}
    assert (await client.post("/api/v1/auth/register", json=payload)).status_code == 201
    response = await client.post(
        "/api/v1/auth/register",
        json={**payload, "email": " USER@EXAMPLE.COM "},
    )
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "EMAIL_ALREADY_REGISTERED"
```

Add tests proving:

```text
wrong password -> 401 INVALID_CREDENTIALS
unknown email -> same 401 INVALID_CREDENTIALS
access token sent to /auth/refresh -> 401 INVALID_TOKEN
refresh token sent as Bearer to /auth/me -> 401 INVALID_TOKEN
valid refresh -> new access_token, no replacement refresh_token field required
/auth/me -> id/name/email/preferred_language/timezone only
password_hash never appears in any JSON
7-char password -> 422 VALIDATION_ERROR
129-char password -> 422 VALIDATION_ERROR
```

- [ ] **Step 2: Run auth tests and verify RED**

```bash
cd backend
uv run pytest tests/test_auth.py -v
```

Expected: API tests fail because auth routes/security do not exist.

- [ ] **Step 3: Add security dependencies and config**

Add runtime dependencies:

```toml
"PyJWT>=2.10,<3",
"pwdlib[argon2]>=0.2,<1",
"email-validator>=2.2,<3",
```

Run:

```bash
uv lock
```

Extend `Settings`:

```python
jwt_algorithm: str = "HS256"
access_token_minutes: int = 15
refresh_token_days: int = 30
```

- [ ] **Step 4: Implement password and JWT primitives**

`backend/app/auth/security.py`:

```python
from datetime import UTC, datetime, timedelta
from uuid import UUID

import jwt
from pwdlib import PasswordHash

password_hash = PasswordHash.recommended()


def hash_password(value: str) -> str:
    return password_hash.hash(value)


def verify_password(value: str, encoded: str) -> bool:
    return password_hash.verify(value, encoded)


def create_access_token(user_id: UUID) -> str:
    return _create_token(user_id, "access", timedelta(minutes=settings.access_token_minutes))


def create_refresh_token(user_id: UUID) -> str:
    return _create_token(user_id, "refresh", timedelta(days=settings.refresh_token_days))
```

`decode_token(token, expected_type)` must reject invalid signature, expiry, malformed `sub`, and wrong `type` with the same `INVALID_TOKEN` API error.

- [ ] **Step 5: Implement the common error envelope**

`ApiError` carries `status_code`, `code`, `message`, `details`. Register handlers in `main.py` for `ApiError` and FastAPI `RequestValidationError`:

```python
return JSONResponse(
    status_code=422,
    content={
        "error": {
            "code": "VALIDATION_ERROR",
            "message": "Request validation failed.",
            "details": {"fields": normalized_errors},
        }
    },
)
```

Do not change `/health` and `/ready` semantics in this task.

- [ ] **Step 6: Implement transactional register/login/refresh/me**

Registration service pseudocode must be implemented as one transaction:

```python
normalized_email = payload.email.strip().lower()
existing = await session.scalar(select(User).where(User.email == normalized_email))
if existing:
    raise ApiError(409, "EMAIL_ALREADY_REGISTERED", "An account already uses this email.")

user = User(..., password_hash=hash_password(payload.password))
family = Family(name=f"{user.name}'s family", created_by_user_id=user.id)
membership = FamilyMembership(..., role="owner", status="active")
session.add_all([user, family, membership])
await session.commit()
```

Use `await session.flush()` where IDs are needed before commit.

`get_current_user()` reads a Bearer access token, validates `type=access`, loads the user, and returns 401 `INVALID_TOKEN` if the user no longer exists.

- [ ] **Step 7: Wire router**

In `main.py`:

```python
app.include_router(auth_router, prefix="/api/v1/auth")
```

Expected statuses:

```text
POST /auth/register -> 201
POST /auth/login -> 200
POST /auth/refresh -> 200
GET  /auth/me -> 200
```

- [ ] **Step 8: Run auth + legacy tests**

```bash
cd backend
uv run ruff check .
uv run pytest tests/test_auth.py tests/test_config.py tests/test_health.py -v
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add backend
git commit -m "feat: add email password authentication"
```

---

### Task 3: Backend family-member API and authorization boundary

**Files:**
- Create: `backend/app/families/schemas.py`
- Create: `backend/app/families/repository.py`
- Create: `backend/app/families/service.py`
- Create: `backend/app/families/router.py`
- Modify: `backend/app/main.py`
- Create/Test: `backend/tests/test_family_members.py`

**Interfaces:**
- Consumes: `get_current_user()`, `FamilyMembership`, `FamilyMember`, `AsyncSession`.
- Produces: `require_accessible_member(session, user_id, member_id) -> FamilyMember` plus GET/POST/PATCH family-member APIs.

- [ ] **Step 1: Write failing family API tests**

Tests must cover create/list/read/update, archived exclusion, future DOB, invalid timezone, and cross-family 404:

```python
async def test_create_family_member(client, auth_headers):
    response = await client.post(
        "/api/v1/family-members",
        headers=auth_headers,
        json={
            "name": "Amma",
            "relationship": "mother",
            "preferred_language": "bn",
            "timezone": "Asia/Dhaka",
        },
    )
    assert response.status_code == 201
    assert response.json()["name"] == "Amma"
    assert response.json()["preferred_language"] == "bn"
```

Review-focus tests:

```text
future DOB -> 422 VALIDATION_ERROR
"Not/A_Real_Zone" -> 422 VALIDATION_ERROR
user A GET user B member -> 404 FAMILY_MEMBER_NOT_FOUND
user A PATCH user B member -> 404 FAMILY_MEMBER_NOT_FOUND
```

- [ ] **Step 2: Run tests and verify RED**

```bash
cd backend
uv run pytest tests/test_family_members.py -v
```

Expected: 404 route-not-found or import failure.

- [ ] **Step 3: Implement schemas and validation**

Use Pydantic field validators:

```python
@field_validator("timezone")
@classmethod
def valid_timezone(cls, value: str) -> str:
    try:
        ZoneInfo(value)
    except ZoneInfoNotFoundError as exc:
        raise ValueError("invalid IANA timezone") from exc
    return value
```

DOB validator compares to `date.today()`. `preferred_language` is `Literal["en", "bn"]`.

- [ ] **Step 4: Implement membership-scoped repository helpers**

The accessible-member query must join membership to the member's family rather than loading the member first and checking later:

```python
stmt = (
    select(FamilyMember)
    .join(FamilyMembership, FamilyMembership.family_id == FamilyMember.family_id)
    .where(
        FamilyMember.id == member_id,
        FamilyMembership.user_id == user_id,
        FamilyMembership.status == "active",
        FamilyMember.archived_at.is_(None),
    )
)
```

If no row exists, raise 404 `FAMILY_MEMBER_NOT_FOUND`.

- [ ] **Step 5: Implement create/list/read/update service + router**

For V1 creation, determine the current user's active owner family. If none exists, treat it as an internal consistency failure rather than silently creating another family.

PATCH may update only:

```text
name
relationship
date_of_birth
preferred_language
timezone
```

Do not expose archive/delete actions in this slice.

- [ ] **Step 6: Wire router and run tests**

```bash
cd backend
uv run ruff check .
uv run pytest tests/test_family_members.py tests/test_auth.py -v
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add backend/app/families backend/app/main.py backend/tests/test_family_members.py
git commit -m "feat: add family member APIs"
```

---

### Task 4: Backend manual-medication API with cross-family protection

**Files:**
- Create: `backend/app/medications/schemas.py`
- Create: `backend/app/medications/repository.py`
- Create: `backend/app/medications/service.py`
- Create: `backend/app/medications/router.py`
- Modify: `backend/app/main.py`
- Create/Test: `backend/tests/test_medications.py`

**Interfaces:**
- Consumes: `require_accessible_member()`, `get_current_user()`, `MemberMedication`.
- Produces: `require_accessible_medication(session, user_id, medication_id) -> MemberMedication` and manual medication endpoints.

- [ ] **Step 1: Write failing medication API tests**

Core test:

```python
async def test_create_manual_medication_is_draft(client, auth_headers, amma):
    response = await client.post(
        f"/api/v1/family-members/{amma['id']}/medications",
        headers=auth_headers,
        json={
            "display_name": " Metformin ",
            "strength": "500 mg",
            "dosage_form": "tablet",
            "start_date": "2026-09-23",
        },
    )
    assert response.status_code == 201
    body = response.json()
    assert body["display_name"] == "Metformin"
    assert body["status"] == "draft"
    assert body["medicine_master_id"] is None
```

Add tests for:

```text
end_date before start_date -> 422 VALIDATION_ERROR
empty/whitespace display_name -> 422
list only medications for requested member
PATCH cannot accept status
PATCH allowed fields persist
user A list/create under user B member -> 404 FAMILY_MEMBER_NOT_FOUND
user A GET/PATCH user B medication -> 404 MEDICATION_NOT_FOUND
```

- [ ] **Step 2: Run and verify RED**

```bash
cd backend
uv run pytest tests/test_medications.py -v
```

Expected: route/import failures.

- [ ] **Step 3: Implement schemas**

Creation schema fields:

```python
class ManualMedicationCreate(BaseModel):
    display_name: str = Field(min_length=1, max_length=180)
    strength: str | None = Field(default=None, max_length=80)
    dosage_form: str | None = Field(default=None, max_length=80)
    start_date: date
    end_date: date | None = None
```

Use a model validator to reject `end_date < start_date`; trim optional strings and convert blank optional strings to `None`.

- [ ] **Step 4: Implement repository authorization query**

Medication access query joins:

```text
member_medications
-> family_members
-> family_memberships
```

and filters active membership for the current user in one statement. Missing/inaccessible row returns 404 `MEDICATION_NOT_FOUND`.

- [ ] **Step 5: Implement API**

Routes:

```text
GET   /api/v1/family-members/{member_id}/medications -> 200
POST  /api/v1/family-members/{member_id}/medications -> 201
GET   /api/v1/member-medications/{medication_id} -> 200
PATCH /api/v1/member-medications/{medication_id} -> 200
```

Create values are server-controlled:

```python
MemberMedication(
    family_member_id=member.id,
    medicine_master_id=None,
    prescription_id=None,
    extraction_id=None,
    status="draft",
    created_by_user_id=current_user.id,
    ...
)
```

Never accept `status`, `family_member_id`, `medicine_master_id`, `created_by_user_id`, `prescription_id`, or `extraction_id` from the manual-create/PATCH client contract.

- [ ] **Step 6: Run complete backend verification**

```bash
cd backend
uv run ruff check .
uv run alembic upgrade head
uv run pytest -v
```

Expected: all backend tests PASS.

- [ ] **Step 7: Commit**

```bash
git add backend
git commit -m "feat: add manual medication APIs"
```

---

### Task 5: Flutter auth infrastructure, secure token storage, and refresh gate

**Files:**
- Modify: `mobile/pubspec.yaml`
- Modify generated: `mobile/pubspec.lock`
- Modify: `mobile/lib/main.dart`
- Create: `mobile/lib/core/api/api_error.dart`
- Create: `mobile/lib/core/api/api_client.dart`
- Create: `mobile/lib/core/auth/auth_tokens.dart`
- Create: `mobile/lib/core/auth/auth_state.dart`
- Create: `mobile/lib/core/auth/auth_controller.dart`
- Create: `mobile/lib/core/auth/token_store.dart`
- Create: `mobile/lib/core/storage/secure_token_store.dart`
- Create: `mobile/lib/features/auth/domain/current_user.dart`
- Create: `mobile/lib/features/auth/data/auth_repository.dart`
- Create/Test: `mobile/test/core/api/api_client_test.dart`
- Create/Test: `mobile/test/core/auth/auth_controller_test.dart`

**Interfaces:**
- Consumes backend `/auth/login`, `/auth/register`, `/auth/refresh`, `/auth/me`.
- Produces providers for `TokenStore`, `ApiClient`, `AuthRepository`, and `AuthController`; `AuthState` exposes `loading|unauthenticated|authenticated` plus `CurrentUser`.

- [ ] **Step 1: Add failing auth-state/token tests first**

Define a fake token store and fake auth repository. Tests must prove:

```text
restore with no refresh token -> unauthenticated
restore with stored session + successful /me -> authenticated
restore requiring access refresh -> authenticated after new access token is saved
unrecoverable restore/refresh -> tokens cleared + unauthenticated
logout -> tokens cleared + unauthenticated
```

Representative test:

```dart
test('restore clears unrecoverable session', () async {
  final store = FakeTokenStore(AuthTokens('expired-access', 'bad-refresh'));
  final repository = FakeAuthRepository(meError: const AuthFailure.invalidSession());
  final controller = AuthController(repository: repository, tokenStore: store);

  await controller.restore();

  expect(controller.state.status, AuthStatus.unauthenticated);
  expect(await store.read(), isNull);
});
```

- [ ] **Step 2: Add failing concurrent-refresh API test**

Use Dio's test adapter or an injected `HttpClientAdapter`. Fire two protected requests that both receive 401, then assert exactly one `/auth/refresh` request and both original calls retry once with the new token.

The production client must guard refresh with:

```dart
Future<void>? _refreshFuture;

Future<void> _refreshOnce() {
  return _refreshFuture ??= _performRefresh().whenComplete(() {
    _refreshFuture = null;
  });
}
```

- [ ] **Step 3: Run tests and verify RED**

```bash
cd mobile
flutter test test/core/auth/auth_controller_test.dart test/core/api/api_client_test.dart
```

Expected: imports/classes do not exist.

- [ ] **Step 4: Add Flutter dependencies**

Add:

```yaml
flutter_riverpod: ^2.6.1
dio: ^5.9.0
flutter_secure_storage: ^9.2.4
```

Then:

```bash
flutter pub get
```

Do not add local-cache tables for family/medication writes in this slice.

- [ ] **Step 5: Implement token store and typed API errors**

`TokenStore`:

```dart
abstract interface class TokenStore {
  Future<AuthTokens?> read();
  Future<void> write(AuthTokens tokens);
  Future<void> clear();
}
```

Secure storage keys are stable constants such as `familymed.access_token` and `familymed.refresh_token`.

`ApiError` parses the backend envelope's `code`, `message`, and `details`; network/unparseable failures map to a non-sensitive `NETWORK_ERROR`/`UNKNOWN_ERROR` client-side code.

- [ ] **Step 6: Implement API client and refresh behavior**

Rules:

```text
attach access Bearer token to protected calls
on first 401 only -> await shared refresh future
POST refresh using refresh token without the normal auth interceptor loop
save new access token while preserving refresh token
retry original request once
if refresh fails -> clear tokens; surface invalid-session signal
never recursively refresh /auth/login, /auth/register, /auth/refresh
```

Use `RequestOptions.extra['authRetried'] = true` to prevent retry loops.

- [ ] **Step 7: Implement auth repository/controller providers**

`AuthRepository` exact public surface:

```dart
Future<AuthSession> register({required String name, required String email, required String password});
Future<AuthSession> login({required String email, required String password});
Future<CurrentUser> me();
Future<void> refreshAccessToken();
```

`AuthController` handles register/login/restore/logout and owns the app-level auth state; UI screens should not write secure storage directly.

- [ ] **Step 8: Wrap app in ProviderScope**

Modify `main.dart`:

```dart
runApp(const ProviderScope(child: FamilyMedApp()));
```

- [ ] **Step 9: Run tests and analyze**

```bash
flutter test test/core/auth/auth_controller_test.dart test/core/api/api_client_test.dart
flutter analyze
```

Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add mobile
git commit -m "feat: add mobile auth infrastructure"
```

---

### Task 6: Flutter registration/login screens and authenticated routing

**Files:**
- Modify: `mobile/lib/app/app.dart`
- Modify: `mobile/lib/app/router.dart`
- Modify: `mobile/lib/features/welcome/presentation/welcome_screen.dart`
- Create: `mobile/lib/features/auth/presentation/register_screen.dart`
- Create: `mobile/lib/features/auth/presentation/login_screen.dart`
- Modify: `mobile/lib/l10n/app_en.arb`
- Modify: `mobile/lib/l10n/app_bn.arb`
- Modify/Test: `mobile/test/app_test.dart`
- Create/Test: `mobile/test/features/auth/auth_flow_test.dart`

**Interfaces:**
- Consumes: `AuthController`, `AuthState`, `AuthRepository`.
- Produces routes `/welcome`, `/register`, `/login`, guarded authenticated route entry `/family` and onboarding entry `/care-for`.

- [ ] **Step 1: Write failing routing/widget tests**

Tests:

```text
Welcome Get started -> /register
Welcome I already have an account -> /login
7-character password stays client-invalid and no submit call occurs
failed login keeps email text visible and shows backend error text
successful register -> /care-for
successful login with zero members -> /care-for
successful login with one+ members -> /family
unauthenticated direct /family navigation -> /login
```

Use provider overrides with fake `AuthRepository` and fake family repository; do not hit real network in widget tests.

- [ ] **Step 2: Run and verify RED**

```bash
cd mobile
flutter test test/features/auth/auth_flow_test.dart test/app_test.dart
```

Expected: routes/screens/actions missing.

- [ ] **Step 3: Convert app/router to Riverpod-aware configuration**

Make `FamilyMedApp` a `ConsumerWidget` and obtain `routerConfig` from `routerProvider`.

The router redirect logic must distinguish `loading`, `unauthenticated`, and `authenticated`. During initial restore show a small neutral splash/loading screen, not the login screen flashing underneath.

- [ ] **Step 4: Implement Welcome/Register/Login**

Welcome preserves the current logo/headline/body, adds:

```text
Get started
I already have an account
AI assists. You always confirm.
```

Registration inputs:

```text
Name
Email
Password
Create account
```

Login inputs:

```text
Email
Password
Sign in
```

Form controllers must retain values when the backend call fails. Disable submit while a request is in flight.

- [ ] **Step 5: Add English and Bangla keys together**

At minimum add keys for auth labels, actions, validation, generic network/session errors, and returning-account action. Example pairs:

```json
"alreadyHaveAccount": "I already have an account",
"emailLabel": "Email",
"passwordLabel": "Password",
"createAccount": "Create account",
"signIn": "Sign in"
```

```json
"alreadyHaveAccount": "আমার ইতিমধ্যে একটি অ্যাকাউন্ট আছে",
"emailLabel": "ইমেইল",
"passwordLabel": "পাসওয়ার্ড",
"createAccount": "অ্যাকাউন্ট তৈরি করুন",
"signIn": "সাইন ইন"
```

- [ ] **Step 6: Generate and run tests**

```bash
flutter gen-l10n
flutter test test/features/auth/auth_flow_test.dart test/app_test.dart
flutter analyze
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add mobile
git commit -m "feat: add registration login and auth routing"
```

---

### Task 7: Flutter family onboarding, returning family list, and member profile

**Files:**
- Create: `mobile/lib/features/family/domain/family_member.dart`
- Create: `mobile/lib/features/family/data/family_repository.dart`
- Create: `mobile/lib/features/family/presentation/who_do_you_care_for_screen.dart`
- Create: `mobile/lib/features/family/presentation/add_family_member_screen.dart`
- Create: `mobile/lib/features/family/presentation/family_list_screen.dart`
- Create: `mobile/lib/features/family/presentation/member_profile_screen.dart`
- Modify: `mobile/lib/app/router.dart`
- Modify: `mobile/lib/l10n/app_en.arb`
- Modify: `mobile/lib/l10n/app_bn.arb`
- Create/Test: `mobile/test/features/family/family_flow_test.dart`

**Interfaces:**
- Consumes backend family-member endpoints through `ApiClient`.
- Produces `FamilyRepository.listMembers()`, `createMember()`, `getMember()`, `updateMember()`; routes `/care-for`, `/family/new`, `/family`, `/family/:memberId`.

- [ ] **Step 1: Write failing repository/widget tests**

Tests must cover:

```text
Who do you care for? has parent/spouse/child/myself/someone else
select My parent -> add-member route with prefilled relationship
Add Amma submits name=Amma, relationship=mother, preferred_language=bn, timezone=Asia/Dhaka
future DOB rejected before network call
family list renders returning members and Add family member action
member card opens profile
profile empty state shows No medicines yet
Scan prescription — coming soon is visibly disabled
Add manually is enabled
```

- [ ] **Step 2: Run and verify RED**

```bash
cd mobile
flutter test test/features/family/family_flow_test.dart
```

Expected: missing repository/screens/routes.

- [ ] **Step 3: Implement domain model and repository**

`FamilyMember.fromJson` consumes:

```text
id
name
relationship
date_of_birth
preferred_language
timezone
```

Repository exact public surface:

```dart
Future<List<FamilyMember>> listMembers();
Future<FamilyMember> createMember(CreateFamilyMemberInput input);
Future<FamilyMember> getMember(String id);
Future<FamilyMember> updateMember(String id, UpdateFamilyMemberInput input);
```

- [ ] **Step 4: Implement onboarding screens from approved flow**

`WhoDoYouCareForScreen` passes the selected relationship intent through route extra/query data. `AddFamilyMemberScreen` keeps relationship editable and defaults parent onboarding to:

```text
name: blank
relationship: mother (editable)
preferred language: bn
Timezone: Asia/Dhaka
```

Do not collect diagnosis, address, NID, hospital, or unrelated profile data.

- [ ] **Step 5: Implement `/family` and profile screens**

`FamilyListScreen` is intentionally minimal until the Today shell exists. `MemberProfileScreen` loads the member and medications separately, but medication rendering can remain an injected empty/list provider until Task 8 connects the real repository.

Disabled prescription action must render exactly as a disabled affordance and must not navigate.

- [ ] **Step 6: Add l10n keys and run tests**

```bash
flutter gen-l10n
flutter test test/features/family/family_flow_test.dart
flutter analyze
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add mobile
git commit -m "feat: add family onboarding and profiles"
```

---

### Task 8: Flutter manual-medication flow and persisted vertical acceptance

**Files:**
- Create: `mobile/lib/features/medications/domain/member_medication.dart`
- Create: `mobile/lib/features/medications/data/medication_repository.dart`
- Create: `mobile/lib/features/medications/presentation/add_manual_medication_screen.dart`
- Modify: `mobile/lib/features/family/presentation/member_profile_screen.dart`
- Modify: `mobile/lib/app/router.dart`
- Modify: `mobile/lib/l10n/app_en.arb`
- Modify: `mobile/lib/l10n/app_bn.arb`
- Create/Test: `mobile/test/features/medications/manual_medication_flow_test.dart`
- Modify/Test: `mobile/test/features/family/family_flow_test.dart`

**Interfaces:**
- Consumes backend medication endpoints.
- Produces `MedicationRepository.listForMember()`, `createManual()`, `getMedication()`, `updateMedication()` and route `/family/:memberId/medications/new`.

- [ ] **Step 1: Write failing manual-medication tests**

Widget/repository tests:

```text
medicine name required
start date defaults to today
end date before start date blocks submit
strength/dosage form optional
failed network submit retains entered fields
loading state prevents second submit
successful submit returns to profile
profile refresh shows Metformin / 500 mg / tablet / Draft
no frequency/time/meal/reminder fields exist in this form
```

Representative assertion:

```dart
expect(find.text('Metformin'), findsOneWidget);
expect(find.text('500 mg'), findsOneWidget);
expect(find.text('Draft'), findsOneWidget);
expect(find.textContaining('Reminder'), findsNothing);
```

- [ ] **Step 2: Run and verify RED**

```bash
cd mobile
flutter test test/features/medications/manual_medication_flow_test.dart
```

Expected: missing medication feature code.

- [ ] **Step 3: Implement medication model/repository**

Model consumes server-controlled fields including:

```text
id
family_member_id
medicine_master_id
name/display_name
strength
dosage_form
status
start_date
end_date
created_at
updated_at
```

Repository:

```dart
Future<List<MemberMedication>> listForMember(String memberId);
Future<MemberMedication> createManual(String memberId, CreateManualMedicationInput input);
Future<MemberMedication> getMedication(String id);
Future<MemberMedication> updateMedication(String id, UpdateManualMedicationInput input);
```

Client create payload must not send `status`, `medicine_master_id`, `created_by_user_id`, `prescription_id`, or `extraction_id`.

- [ ] **Step 4: Implement form and profile refresh**

Form fields:

```text
Medicine name *
Strength
Dosage form
Start date * (today)
End date
```

On success:

```dart
await medicationRepository.createManual(...);
ref.invalidate(memberMedicationsProvider(memberId));
context.pop();
```

Member profile reads the refreshed medication list and shows a draft status label. Do not present draft as an active reminder routine.

- [ ] **Step 5: Add English/Bangla medication copy**

Include keys for add-manually, medicine fields, no-medicines state, draft status, invalid date range, and retryable network errors.

- [ ] **Step 6: Run feature tests**

```bash
flutter gen-l10n
flutter test test/features/medications/manual_medication_flow_test.dart test/features/family/family_flow_test.dart
flutter analyze
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add mobile
git commit -m "feat: add manual medication flow"
```

---

### Task 9: End-to-end slice hardening, localization, and clean CI gate

**Files:**
- Modify as needed only for verified failures in previous tasks.
- Modify: `README.md` only if local run instructions need the mobile API base URL documented.
- Test: all backend/mobile tests.

**Interfaces:**
- Consumes: all prior task interfaces.
- Produces: one merge-ready branch satisfying the approved acceptance flow.

- [ ] **Step 1: Run a spec-focused backend test selection**

```bash
cd backend
uv run pytest \
  tests/test_auth.py \
  tests/test_family_members.py \
  tests/test_medications.py -v
```

Expected: all PASS, including all five Review Focus conditions owned by backend.

- [ ] **Step 2: Run full backend verification from migrated PostgreSQL**

```bash
uv run ruff check .
uv run alembic downgrade base
uv run alembic upgrade head
uv run pytest -v
```

Expected: PASS. Restore database to `head` before leaving the task.

- [ ] **Step 3: Run full mobile verification**

```bash
cd ../mobile
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter build apk --debug
```

Expected: PASS.

- [ ] **Step 4: Verify the acceptance flow with integration-style fakes or a local API run**

The test must cover, in order:

```text
register Sifat
-> secure tokens written
-> /care-for
-> select My parent
-> create Amma / mother / bn / Asia/Dhaka
-> Amma profile has no medicines
-> Add manually
-> create Metformin / 500 mg / tablet / today
-> return profile and see Metformin as Draft
-> simulate app relaunch using stored tokens
-> /auth/me restores account
-> family list loads Amma
-> Amma profile reloads Metformin from repository/backend data
```

Name this Flutter test so it is obvious in CI, e.g. `test/features/vertical_slice_acceptance_test.dart`.

- [ ] **Step 5: Verify no scope creep**

Run repository searches:

```bash
git grep -nE "dose|notification|ocr|prescription upload|schedule_time" -- backend/app mobile/lib || true
```

Expected: only approved copy such as disabled prescription-coming-soon text or existing product description; no newly implemented schedule/dose/OCR/notification subsystems.

- [ ] **Step 6: Verify secrets and password fields are not serialized/logged**

```bash
git grep -nE "print\(.*token|print\(.*password|password_hash.*response|refresh_token.*log" -- backend mobile || true
```

Expected: no unsafe logging/serialization code.

- [ ] **Step 7: Commit verification-only fixes, if any**

If Steps 1-6 required code fixes, commit only those verified fixes:

```bash
git add -A
git commit -m "test: harden auth family medication slice"
```

If no files changed, do not create an empty commit.

- [ ] **Step 8: Open draft PR for authoritative clean CI**

Push `feat/auth-family-medications`, open a draft PR against `main`, and require the repository CI to complete successfully. The PR summary must call out:

```text
email/password auth + /auth/me
family owner creation and scoped member APIs
manual draft-medication APIs
secure mobile session/refresh handling
FamilyMed onboarding + manual medication UI
cross-family authorization tests
```

- [ ] **Step 9: Final whole-branch review before merge recommendation**

Review the diff from `main...feat/auth-family-medications` with special attention to:

```text
JWT type/expiry validation
password hashes never escaping schemas
transactional registration
cross-family 404 behavior
concurrent refresh gate
form value preservation after network failure
draft medicine never presented as active routine
English/Bangla parity
```

Only after the branch and PR CI are green should the finishing workflow present merge/PR/keep options.

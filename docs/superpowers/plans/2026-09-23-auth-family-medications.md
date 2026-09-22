# FamilyMed Auth + Family + Manual Medication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the first real FamilyMed vertical slice: register/login, secure session restore, add Amma, manually add a draft medicine, and reload the persisted member and medicine from FastAPI/PostgreSQL.

**Architecture:** Keep the existing monorepo boundaries. The backend gains SQLAlchemy domain models, one Alembic migration, JWT + Argon2 authentication, membership-scoped family APIs, and membership-scoped manual-medication APIs. Flutter gains Riverpod, Dio, secure token storage, automatic one-shot access-token refresh, authenticated routing, family onboarding/list/profile, and manual medication entry. Schedules, dose events, notifications, Today, prescriptions, OCR/HTR, caregiver sharing, and offline write synchronization remain outside this plan.

**Tech Stack:** Python 3.13, FastAPI, PostgreSQL 17, SQLAlchemy 2.x, Alembic, Pydantic v2, PyJWT, pwdlib/Argon2, pytest, httpx; Flutter/Dart, flutter_riverpod 2.x, Dio 5.x, flutter_secure_storage, go_router, Flutter localization, existing FamilyMed theme.

**Spec:** `docs/superpowers/specs/2026-09-23-auth-family-medications-design.md`

## Global Constraints

- Work only on `feat/auth-family-medications` until the finishing workflow.
- Email/password only. Name is trimmed 1-120 chars; email is syntactically valid, trimmed, lowercased; password is 8-128 chars.
- Access JWT lifetime is 15 minutes; refresh JWT lifetime is 30 days. Both contain `sub=<user UUID>` and `type=access|refresh`.
- `/auth/refresh` returns a new access token; the submitted refresh token remains valid until expiry. No revocation or true rotation is implemented.
- Passwords use Argon2 and never appear in API output or logs.
- Registration creates User + Family + active owner FamilyMembership in one DB transaction.
- Cross-family member/medication access returns 404, never a revealing 403.
- Family-member language is exactly `en` or `bn`; DOB cannot be future; timezone must be a valid IANA zone. Flutter defaults new members to `Asia/Dhaka`.
- Manual medicines have `medicine_master_id=NULL`, server-controlled `status=draft`, required `start_date`, and `end_date >= start_date` when present.
- `prescription_id` and `extraction_id` are nullable UUID columns without FKs in this migration.
- No schedule, dose, reminder, Today, prescription upload, OCR/HTR, medicine-catalog import, caregiver invitation, or offline write-sync implementation.
- Every new mobile string is in both `app_en.arb` and `app_bn.arb`; widgets contain no new hard-coded user-facing copy.
- Existing FamilyMed teal/cream theme stays authoritative; primary controls remain at least ~44-48 px high.

## Review Focus

1. **Normalized-email collision:** ` User@Example.com ` then `user@example.com` must result in one account and a 409 on the second registration.
2. **JWT type/session failure:** access tokens cannot refresh, refresh tokens cannot authorize protected routes, and unrecoverable mobile refresh failure clears tokens and auth state.
3. **Cross-family UUID probing:** user A gets 404 for user B's member/medication on read, list, create, and update paths.
4. **Invalid dates/timezone:** future DOB, invalid IANA timezone, and medication end-before-start return the standard validation envelope.
5. **Concurrent mobile 401s:** two simultaneous 401 responses trigger one refresh request and both original calls retry once with the new access token.

---

## Locked interfaces

### Backend auth JSON

Register/login success:

```json
{
  "user": {
    "id": "uuid",
    "name": "Sifat",
    "email": "sifat@example.com",
    "preferred_language": "en",
    "timezone": "Asia/Dhaka"
  },
  "access_token": "jwt",
  "refresh_token": "jwt",
  "token_type": "bearer"
}
```

Refresh request/response:

```json
{"refresh_token": "jwt"}
```

```json
{"access_token": "new-jwt", "token_type": "bearer"}
```

Standard error:

```json
{
  "error": {
    "code": "MACHINE_READABLE_CODE",
    "message": "Human-readable message",
    "details": {}
  }
}
```

### Mobile domain interfaces

```dart
abstract interface class TokenStore {
  Future<AuthTokens?> read();
  Future<void> write(AuthTokens tokens);
  Future<void> clear();
}
```

```dart
abstract interface class AuthRepository {
  Future<AuthSession> register({required String name, required String email, required String password});
  Future<AuthSession> login({required String email, required String password});
  Future<CurrentUser> me();
}
```

```dart
abstract interface class FamilyRepository {
  Future<List<FamilyMember>> listMembers();
  Future<FamilyMember> createMember(CreateFamilyMemberInput input);
  Future<FamilyMember> getMember(String id);
  Future<FamilyMember> updateMember(String id, UpdateFamilyMemberInput input);
}
```

```dart
abstract interface class MedicationRepository {
  Future<List<MemberMedication>> listForMember(String memberId);
  Future<MemberMedication> createManual(String memberId, CreateManualMedicationInput input);
  Future<MemberMedication> getMedication(String id);
  Future<MemberMedication> updateMedication(String id, UpdateManualMedicationInput input);
}
```

---

### Task 1: Backend models, isolated DB tests, and migration

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
- Create via Alembic: `backend/migrations/versions/0002_auth_family_medications.py`
- Create: `backend/tests/conftest.py`
- Create: `backend/tests/test_auth.py`

**Produces:** `Base`, all six domain tables plus `medicine_master`, and rollback-isolated async API/DB test fixtures.

- [ ] **Step 1: Write the failing model test**

`backend/tests/test_auth.py`:

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

- [ ] **Step 2: Run RED**

```bash
cd backend
uv run pytest tests/test_auth.py::test_user_family_membership_models_persist -v
```

Expected: import failure because the model modules do not exist.

- [ ] **Step 3: Add the declarative base and timestamp mixin**

Add to `backend/app/db.py`:

```python
from datetime import datetime
from sqlalchemy import DateTime, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class TimestampMixin:
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), onupdate=func.now()
    )
```

Keep the existing engine/session/readiness functions.

- [ ] **Step 4: Implement the exact model columns**

Use `Mapped[UUID]`, SQLAlchemy `Uuid`, and `default=uuid4` for every PK.

`users`:

```text
id UUID PK
name String(120) NOT NULL
email String(255) NOT NULL UNIQUE INDEX
password_hash Text NOT NULL
preferred_language String(5) NOT NULL default "en"
timezone String(64) NOT NULL default "Asia/Dhaka"
created_at/updated_at timestamptz
```

`families`:

```text
id UUID PK
name String(160) NOT NULL
created_by_user_id UUID FK users.id NOT NULL
created_at/updated_at
```

`family_memberships`:

```text
id UUID PK
family_id UUID FK families.id NOT NULL
user_id UUID FK users.id NOT NULL
role String(20) NOT NULL
status String(20) NOT NULL
created_at timestamptz
UNIQUE(family_id,user_id) named uq_family_membership
INDEX(user_id,status) named ix_family_memberships_user_status
```

`family_members`:

```text
id UUID PK
family_id UUID FK families.id NOT NULL INDEX
name String(120) NOT NULL
relationship String(40) NOT NULL
date_of_birth Date NULL
preferred_language String(5) NOT NULL
linked_user_id UUID FK users.id NULL
profile_image_key Text NULL
timezone String(64) NOT NULL default "Asia/Dhaka"
created_at/updated_at
archived_at timestamptz NULL
```

`medicine_master`:

```text
id UUID PK
brand_name String(160) NULL
generic_name String(160) NOT NULL
strength String(80) NULL
dosage_form String(80) NULL
manufacturer String(160) NULL
country String(2) NOT NULL
source String(120) NOT NULL
source_reference Text NULL
normalized_search_text Text NOT NULL
active Boolean NOT NULL default true
created_at/updated_at
```

`member_medications`:

```text
id UUID PK
family_member_id UUID FK family_members.id NOT NULL
medicine_master_id UUID FK medicine_master.id NULL
prescription_id UUID NULL (no FK)
extraction_id UUID NULL (no FK)
display_name String(180) NOT NULL
strength String(80) NULL
dosage_form String(80) NULL
status String(20) NOT NULL default "draft"
start_date Date NOT NULL
end_date Date NULL
created_by_user_id UUID FK users.id NOT NULL
created_at/updated_at
INDEX(family_member_id,status) named ix_member_medications_member_status
```

- [ ] **Step 5: Add exact rollback-isolated test fixtures**

`backend/tests/conftest.py`:

```python
import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import engine, get_db_session
from app.main import app


@pytest.fixture
async def db_session():
    async with engine.connect() as connection:
        transaction = await connection.begin()
        session = AsyncSession(
            bind=connection,
            expire_on_commit=False,
            join_transaction_mode="create_savepoint",
        )
        try:
            yield session
        finally:
            await session.close()
            await transaction.rollback()


@pytest.fixture
async def client(db_session):
    async def override_db_session():
        yield db_session

    app.dependency_overrides[get_db_session] = override_db_session
    try:
        async with AsyncClient(
            transport=ASGITransport(app=app),
            base_url="http://test",
        ) as test_client:
            yield test_client
    finally:
        app.dependency_overrides.clear()
```

- [ ] **Step 6: Register metadata and generate the exact migration**

`backend/app/models.py` imports all model classes so metadata registration is deterministic. Update `migrations/env.py` to:

```python
import app.models  # noqa: F401
from app.db import Base

target_metadata = Base.metadata
```

Generate:

```bash
uv run alembic revision --autogenerate --rev-id 0002 -m "auth family medications"
```

Expected file: `migrations/versions/0002_auth_family_medications.py`, with `revision = "0002"` and `down_revision = "0001_bootstrap"`. Inspect it and verify it creates exactly the tables, FKs, unique constraint, and indexes listed in Step 4; no unrelated operations.

- [ ] **Step 7: Verify migration + model test**

```bash
uv run alembic downgrade base
uv run alembic upgrade head
uv run pytest tests/test_auth.py::test_user_family_membership_models_persist -v
uv run ruff check .
```

Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add backend
git commit -m "feat: add auth family medication persistence"
```

---

### Task 2: Backend auth, error envelope, and `/auth/me`

**Files:**
- Modify: `backend/pyproject.toml`, `backend/uv.lock`, `backend/app/config.py`, `backend/app/main.py`
- Create: `backend/app/common/__init__.py`, `backend/app/common/errors.py`, `backend/app/common/auth.py`
- Create: `backend/app/auth/__init__.py`, `backend/app/auth/security.py`, `backend/app/auth/schemas.py`, `backend/app/auth/service.py`, `backend/app/auth/router.py`
- Modify: `backend/tests/test_auth.py`

**Produces:** `/api/v1/auth/register`, `/login`, `/refresh`, `/me`, `get_current_user()`.

- [ ] **Step 1: Add failing auth tests**

Add tests with these exact expected outcomes:

```text
register " USER@Example.com " -> 201 and returned email user@example.com
second register user@example.com -> 409 EMAIL_ALREADY_REGISTERED
DB password_hash != submitted password and begins with an Argon2 encoding
wrong password -> 401 INVALID_CREDENTIALS
unknown email -> identical 401 INVALID_CREDENTIALS message
7-char or 129-char password -> 422 VALIDATION_ERROR
access token submitted to /auth/refresh -> 401 INVALID_TOKEN
refresh token as Bearer on /auth/me -> 401 INVALID_TOKEN
valid refresh -> 200 with access_token + token_type only
/auth/me -> id,name,email,preferred_language,timezone and no password_hash
no Bearer token on /auth/me -> 401 INVALID_TOKEN
```

Review Focus #1 and #2 are pinned here.

- [ ] **Step 2: Run RED**

```bash
uv run pytest tests/test_auth.py -v
```

Expected: auth route/import failures.

- [ ] **Step 3: Add dependencies/config**

Add runtime dependencies:

```toml
"PyJWT>=2.10,<3",
"pwdlib[argon2]>=0.2,<1",
"email-validator>=2.2,<3",
```

Then:

```bash
uv lock
```

Add settings:

```python
jwt_algorithm: str = "HS256"
access_token_minutes: int = 15
refresh_token_days: int = 30
```

- [ ] **Step 4: Implement `security.py` exactly around token type**

```python
from datetime import UTC, datetime, timedelta
from uuid import UUID

import jwt
from pwdlib import PasswordHash

from app.config import get_settings

settings = get_settings()
password_hasher = PasswordHash.recommended()


def hash_password(value: str) -> str:
    return password_hasher.hash(value)


def verify_password(value: str, encoded: str) -> bool:
    return password_hasher.verify(value, encoded)


def _create_token(user_id: UUID, token_type: str, lifetime: timedelta) -> str:
    now = datetime.now(UTC)
    return jwt.encode(
        {"sub": str(user_id), "type": token_type, "iat": now, "exp": now + lifetime},
        settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
    )


def create_access_token(user_id: UUID) -> str:
    return _create_token(user_id, "access", timedelta(minutes=settings.access_token_minutes))


def create_refresh_token(user_id: UUID) -> str:
    return _create_token(user_id, "refresh", timedelta(days=settings.refresh_token_days))
```

`decode_token(token, expected_type)` decodes using only `[settings.jwt_algorithm]`, parses `sub` as UUID, checks exact `type`, and maps `ExpiredSignatureError`, `InvalidTokenError`, bad UUID, missing claims, and wrong type to `ApiError(401, "INVALID_TOKEN", "Authentication is invalid or expired.")`.

- [ ] **Step 5: Implement standard errors**

`ApiError` stores status/code/message/details. Add exception handlers in `main.py` for `ApiError` and `RequestValidationError`. Validation handler returns status 422 and:

```python
{
    "error": {
        "code": "VALIDATION_ERROR",
        "message": "Request validation failed.",
        "details": {"fields": exc.errors()},
    }
}
```

Do not alter existing `/health` or `/ready` HTTPException behavior.

- [ ] **Step 6: Implement exact Pydantic auth schemas**

Use `EmailStr`, `StringConstraints`, and field validators:

```python
Name = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=120)]
Password = Annotated[str, StringConstraints(min_length=8, max_length=128)]

class RegisterRequest(BaseModel):
    name: Name
    email: EmailStr
    password: Password

    @field_validator("email", mode="before")
    @classmethod
    def normalize_email(cls, value):
        return str(value).strip().lower()
```

`LoginRequest` uses normalized `EmailStr` + password string. `RefreshRequest` has `refresh_token: str`. `UserResponse` exposes only `id,name,email,preferred_language,timezone`. `AuthResponse` and `RefreshResponse` match Locked interfaces above.

- [ ] **Step 7: Implement atomic registration and login**

Registration runs its lookup and inserts inside one `async with session.begin()` block, flushing after User and Family inserts to obtain IDs. Catch `IntegrityError` around the transaction and map email uniqueness races to the same 409 code.

Create:

```text
User(name trimmed, email normalized, password_hash Argon2)
Family(name="<trimmed name>'s family", created_by_user_id=user.id)
FamilyMembership(family_id=family.id,user_id=user.id,role="owner",status="active")
```

Login performs one email lookup, verifies Argon2, and returns the same generic `INVALID_CREDENTIALS` response for unknown email and wrong password.

- [ ] **Step 8: Implement `get_current_user()` and routes**

Use `HTTPBearer(auto_error=False)`. Only `type=access` succeeds. Load User by JWT `sub`; missing/deleted user maps to `INVALID_TOKEN`.

Wire:

```text
POST /api/v1/auth/register -> 201 AuthResponse
POST /api/v1/auth/login -> 200 AuthResponse
POST /api/v1/auth/refresh -> 200 RefreshResponse
GET  /api/v1/auth/me -> 200 UserResponse
```

- [ ] **Step 9: Verify + commit**

```bash
uv run ruff check .
uv run pytest tests/test_auth.py tests/test_config.py tests/test_health.py -v
git add backend
git commit -m "feat: add email password authentication"
```

---

### Task 3: Backend family-member APIs with one-query ownership checks

**Files:**
- Create: `backend/app/families/schemas.py`, `repository.py`, `service.py`, `router.py`
- Modify: `backend/app/main.py`
- Create: `backend/tests/test_family_members.py`

**Produces:** `require_accessible_member(session,user_id,member_id)` and family-member list/create/read/update APIs.

- [ ] **Step 1: Write failing tests**

Test:

```text
create Amma/mother/bn/Asia-Dhaka -> 201
list returns Amma for owner
GET returns Amma
PATCH relationship/name/language/timezone/DOB -> persists
future DOB -> 422 VALIDATION_ERROR
invalid timezone Not/A_Real_Zone -> 422 VALIDATION_ERROR
user A GET user B member -> 404 FAMILY_MEMBER_NOT_FOUND
user A PATCH user B member -> 404 FAMILY_MEMBER_NOT_FOUND
archived_at non-null row is omitted from normal list
```

Review Focus #3 and family portion of #4 are pinned here.

- [ ] **Step 2: Run RED**

```bash
uv run pytest tests/test_family_members.py -v
```

- [ ] **Step 3: Implement schema validation**

Use trimmed constrained strings, `Literal["en","bn"]`, a DOB validator against `date.today()`, and:

```python
@field_validator("timezone")
@classmethod
def validate_timezone(cls, value: str) -> str:
    try:
        ZoneInfo(value)
    except ZoneInfoNotFoundError as exc:
        raise ValueError("invalid IANA timezone") from exc
    return value
```

Create request requires `name,relationship,preferred_language,timezone`; DOB optional. PATCH fields are all optional but use the same validators.

- [ ] **Step 4: Implement repository queries**

Accessible member query must join before returning the row:

```python
select(FamilyMember).join(
    FamilyMembership, FamilyMembership.family_id == FamilyMember.family_id
).where(
    FamilyMember.id == member_id,
    FamilyMembership.user_id == user_id,
    FamilyMembership.status == "active",
    FamilyMember.archived_at.is_(None),
)
```

No row -> `ApiError(404,"FAMILY_MEMBER_NOT_FOUND","Family member was not found.")`.

For create, select exactly one active membership with role in `{"owner","caregiver"}`; V1 registration produces only owner. If none exists, return 409 `FAMILY_CONTEXT_MISSING`.

- [ ] **Step 5: Implement routes**

```text
GET   /api/v1/family-members -> non-archived accessible members
POST  /api/v1/family-members -> 201
GET   /api/v1/family-members/{member_id} -> 200 or scoped 404
PATCH /api/v1/family-members/{member_id} -> 200 or scoped 404
```

All require `get_current_user()`.

- [ ] **Step 6: Verify + commit**

```bash
uv run ruff check .
uv run pytest tests/test_family_members.py tests/test_auth.py -v
git add backend/app/families backend/app/main.py backend/tests/test_family_members.py
git commit -m "feat: add family member APIs"
```

---

### Task 4: Backend manual-medication APIs

**Files:**
- Create: `backend/app/medications/schemas.py`, `repository.py`, `service.py`, `router.py`
- Modify: `backend/app/main.py`
- Create: `backend/tests/test_medications.py`

**Produces:** `require_accessible_medication()` plus member medication list/create/read/update.

- [ ] **Step 1: Write failing tests**

Test exact behavior:

```text
create Metformin/500 mg/tablet -> 201, status draft, medicine_master_id null
whitespace display_name -> 422 VALIDATION_ERROR
blank optional strength/form -> persisted as null
end_date before start_date -> 422 VALIDATION_ERROR
list is limited to requested authorized member
PATCH name/strength/form/start/end -> persists
PATCH payload containing status -> ignored/rejected by schema and never changes status
user A list/create under user B member -> 404 FAMILY_MEMBER_NOT_FOUND
user A GET/PATCH user B medication -> 404 MEDICATION_NOT_FOUND
```

Review Focus #3 and medication portion of #4 are pinned here.

- [ ] **Step 2: Run RED**

```bash
uv run pytest tests/test_medications.py -v
```

- [ ] **Step 3: Implement schemas**

```python
class ManualMedicationCreate(BaseModel):
    display_name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=180)]
    strength: Annotated[str | None, StringConstraints(strip_whitespace=True, max_length=80)] = None
    dosage_form: Annotated[str | None, StringConstraints(strip_whitespace=True, max_length=80)] = None
    start_date: date
    end_date: date | None = None

    @model_validator(mode="after")
    def validate_dates(self):
        if self.end_date is not None and self.end_date < self.start_date:
            raise ValueError("end date cannot be before start date")
        if self.strength == "":
            self.strength = None
        if self.dosage_form == "":
            self.dosage_form = None
        return self
```

PATCH exposes only these five identity/date fields; do not define status/member/master/prescription/extraction/creator fields in client schemas.

- [ ] **Step 4: Implement scoped repository + server-controlled create**

`require_accessible_medication` joins `MemberMedication -> FamilyMember -> FamilyMembership` and filters active membership/current user in one statement. Missing/inaccessible -> 404 `MEDICATION_NOT_FOUND`.

Create always sets:

```python
medicine_master_id=None
prescription_id=None
extraction_id=None
status="draft"
created_by_user_id=current_user.id
```

- [ ] **Step 5: Implement routes**

```text
GET   /api/v1/family-members/{member_id}/medications
POST  /api/v1/family-members/{member_id}/medications -> 201
GET   /api/v1/member-medications/{medication_id}
PATCH /api/v1/member-medications/{medication_id}
```

- [ ] **Step 6: Full backend gate + commit**

```bash
uv run ruff check .
uv run alembic upgrade head
uv run pytest -v
git add backend
git commit -m "feat: add manual medication APIs"
```

---

### Task 5: Flutter secure session infrastructure and concurrent refresh gate

**Files:**
- Modify: `mobile/pubspec.yaml`, generated `mobile/pubspec.lock`, `mobile/lib/main.dart`
- Create: `mobile/lib/core/api/api_config.dart`, `api_error.dart`, `api_client.dart`
- Create: `mobile/lib/core/auth/auth_tokens.dart`, `auth_state.dart`, `auth_controller.dart`, `token_store.dart`, `session_events.dart`
- Create: `mobile/lib/core/storage/secure_token_store.dart`
- Create: `mobile/lib/features/auth/domain/current_user.dart`, `auth_session.dart`
- Create: `mobile/lib/features/auth/data/auth_repository.dart`
- Create: `mobile/test/core/api/api_client_test.dart`, `mobile/test/core/auth/auth_controller_test.dart`

**Produces:** secure session storage, shared refresh future, auth state used by router.

- [ ] **Step 1: Add dependencies**

```yaml
flutter_riverpod: ^2.6.1
dio: ^5.9.0
flutter_secure_storage: ^9.2.4
```

Dev dependency for deterministic Dio tests:

```yaml
http_mock_adapter: ^0.6.1
```

Run `flutter pub get`.

- [ ] **Step 2: Write RED auth-controller tests**

Use `FakeTokenStore` and `FakeAuthRepository` implementing Locked interfaces. Test:

```text
no stored tokens -> unauthenticated
stored tokens + /me succeeds -> authenticated
/me succeeds after ApiClient refresh -> new access token remains stored
ApiError(code: INVALID_TOKEN) during restore -> store cleared, unauthenticated
logout -> store cleared, unauthenticated
SessionEvents.expired event -> store cleared, unauthenticated
```

No undefined `AuthFailure` type is used; fake repositories throw the same `ApiError` type used by production data code.

- [ ] **Step 3: Write RED concurrent-refresh test**

With `DioAdapter`, configure two protected requests to return 401 for `old-access`, one `/auth/refresh` response returning `new-access`, and retries returning 200. Execute `Future.wait` for both calls. Assert:

```dart
expect(refreshRequestCount, 1);
expect((await tokenStore.read())!.accessToken, 'new-access');
expect(result1.statusCode, 200);
expect(result2.statusCode, 200);
```

Review Focus #5 is pinned here.

- [ ] **Step 4: Implement token/session primitives**

`AuthTokens` holds `accessToken` + `refreshToken`. `SecureTokenStore` uses keys:

```text
familymed.access_token
familymed.refresh_token
```

`SessionEvents` exposes a broadcast `Stream<void> get expired` and `notifyExpired()`; `AuthController` subscribes and sets unauthenticated after clearing tokens.

- [ ] **Step 5: Implement API config/client**

Default base URL:

```dart
const apiBaseUrl = String.fromEnvironment(
  'FAMILYMED_API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000/api/v1',
);
```

`ApiClient` owns normal Dio + refresh Dio + TokenStore + SessionEvents. Protected calls attach access token. First 401 only:

```dart
Future<void>? _refreshFuture;
Future<void> _refreshOnce() => _refreshFuture ??= _performRefresh().whenComplete(() {
  _refreshFuture = null;
});
```

`_performRefresh()` posts JSON `{refresh_token: stored.refreshToken}` using refresh Dio, replaces only the access token, and preserves refresh token. On failure it clears storage, emits `SessionEvents.notifyExpired()`, and throws `ApiError(code:'INVALID_TOKEN',...)`. Retried requests carry `extra['authRetried']=true`; login/register/refresh endpoints never enter the refresh loop.

- [ ] **Step 6: Implement auth repository/controller**

`AuthRepository` has only the three Locked methods (`register`, `login`, `me`). Login/register write tokens through `AuthController`, not repository. `AuthController.restore()` reads tokens; no token -> unauthenticated; stored token -> `repository.me()`; ApiClient performs refresh transparently if access expired.

- [ ] **Step 7: Wrap app and verify**

`main.dart`:

```dart
runApp(const ProviderScope(child: FamilyMedApp()));
```

Then:

```bash
flutter test test/core/auth/auth_controller_test.dart test/core/api/api_client_test.dart
flutter analyze
git add mobile
git commit -m "feat: add mobile auth infrastructure"
```

---

### Task 6: Flutter registration/login and auth-aware routing

**Files:**
- Modify: `mobile/lib/app/app.dart`, `mobile/lib/app/router.dart`, `mobile/lib/features/welcome/presentation/welcome_screen.dart`
- Create: `mobile/lib/features/auth/presentation/register_screen.dart`, `login_screen.dart`
- Modify: `mobile/lib/l10n/app_en.arb`, `app_bn.arb`
- Modify: `mobile/test/app_test.dart`
- Create: `mobile/test/features/auth/auth_flow_test.dart`

- [ ] **Step 1: Write RED widget/router tests**

Test:

```text
Welcome Get started -> /register
Welcome existing-account action -> /login
7-char password blocks submit
failed login leaves typed email/password form values intact and shows error
register success -> /care-for
login success + FamilyRepository returns [] -> /care-for
login success + FamilyRepository returns member -> /family
unauthenticated direct /family -> /login
stored authenticated session restored while initial /welcome -> /family
```

- [ ] **Step 2: Implement router provider without auth/repository circularity**

`FamilyMedApp` becomes `ConsumerWidget`. `routerProvider` listens to `authControllerProvider` through a `ChangeNotifier` refresh bridge. Redirect rules:

```text
loading -> /splash
unauthenticated + protected path -> /login
authenticated + /welcome or /splash -> /family
otherwise no redirect
```

Register/login screens explicitly choose `/care-for` vs `/family` after successful action by calling `FamilyRepository.listMembers()`. This keeps family count out of `AuthController`.

- [ ] **Step 3: Implement screens using existing theme**

Welcome keeps logo/headline/body/AI note and adds the existing-account action. Register fields: Name, Email, Password. Login fields: Email, Password. Controllers are not cleared on failed network/backend responses; submit button disables while loading.

- [ ] **Step 4: Add exact auth localization keys**

English/Bangla pairs:

```text
alreadyHaveAccount: I already have an account / আমার ইতিমধ্যে একটি অ্যাকাউন্ট আছে
nameLabel: Name / নাম
emailLabel: Email / ইমেইল
passwordLabel: Password / পাসওয়ার্ড
createAccount: Create account / অ্যাকাউন্ট তৈরি করুন
signIn: Sign in / সাইন ইন
passwordLengthError: Password must be 8–128 characters. / পাসওয়ার্ড ৮–১২৮ অক্ষরের হতে হবে।
invalidEmailError: Enter a valid email address. / সঠিক ইমেইল ঠিকানা লিখুন।
networkError: Could not connect. Try again. / সংযোগ করা যায়নি। আবার চেষ্টা করুন।
```

- [ ] **Step 5: Verify + commit**

```bash
flutter gen-l10n
flutter test test/features/auth/auth_flow_test.dart test/app_test.dart
flutter analyze
git add mobile
git commit -m "feat: add registration login and auth routing"
```

---

### Task 7: Flutter family onboarding/list/profile

**Files:**
- Create: `mobile/lib/features/family/domain/family_member.dart`
- Create: `mobile/lib/features/family/data/family_repository.dart`
- Create: `mobile/lib/features/family/presentation/who_do_you_care_for_screen.dart`, `add_family_member_screen.dart`, `family_list_screen.dart`, `member_profile_screen.dart`
- Modify: `mobile/lib/app/router.dart`, `mobile/lib/l10n/app_en.arb`, `app_bn.arb`
- Create: `mobile/test/features/family/family_flow_test.dart`

- [ ] **Step 1: Write RED tests**

Test parent/spouse/child/myself/someone-else choices; My parent pre-fills relationship `mother` but remains editable; adding Amma submits `bn` + `Asia/Dhaka`; future DOB blocks submit; `/family` renders cards and Add family member; card opens profile; profile renders member identity and no-medicines empty state; prescription action is visibly disabled as coming soon.

Task 7 does not add the active Add-manually navigation yet; Task 8 adds the medication repository and then activates that control, so every intermediate commit remains compilable.

- [ ] **Step 2: Implement repository/domain**

Map `id,name,relationship,date_of_birth,preferred_language,timezone`. Implement exactly the four Locked FamilyRepository methods against backend endpoints.

- [ ] **Step 3: Implement screens/routes**

Routes:

```text
/care-for
/family/new
/family
/family/:memberId
```

Collect only the approved fields. No NID/address/diagnosis/hospital fields.

- [ ] **Step 4: Add exact family localization keys**

```text
familyFirst: Family first / পরিবার সবার আগে
whoDoYouCareFor: Who do you care for? / আপনি কার যত্ন নেন?
myParent: My parent / আমার বাবা বা মা
mySpouse: My spouse / আমার জীবনসঙ্গী
myChild: My child / আমার সন্তান
myself: Myself / আমি নিজে
someoneElse: Someone else / অন্য কেউ
continueLabel: Continue / চালিয়ে যান
familyProfile: Family profile / পরিবারের প্রোফাইল
familyMemberName: Name / নাম
relationshipLabel: Relationship / সম্পর্ক
preferredLanguage: Preferred language / পছন্দের ভাষা
addFamilyMember: Add family member / পরিবারের সদস্য যোগ করুন
yourFamily: Your family / আপনার পরিবার
noMedicinesYet: No medicines yet / এখনো কোনো ওষুধ যোগ করা হয়নি
scanPrescriptionComingSoon: Scan prescription — coming soon / প্রেসক্রিপশন স্ক্যান — শিগগিরই আসছে
```

- [ ] **Step 5: Verify + commit**

```bash
flutter gen-l10n
flutter test test/features/family/family_flow_test.dart
flutter analyze
git add mobile
git commit -m "feat: add family onboarding and profiles"
```

---

### Task 8: Flutter manual medication entry and profile refresh

**Files:**
- Create: `mobile/lib/features/medications/domain/member_medication.dart`
- Create: `mobile/lib/features/medications/data/medication_repository.dart`
- Create: `mobile/lib/features/medications/presentation/add_manual_medication_screen.dart`
- Modify: `mobile/lib/features/family/presentation/member_profile_screen.dart`, `mobile/lib/app/router.dart`, l10n ARBs
- Create: `mobile/test/features/medications/manual_medication_flow_test.dart`
- Modify: `mobile/test/features/family/family_flow_test.dart`

- [ ] **Step 1: Write RED tests**

Test:

```text
Add manually active on member profile
medicine name required
start date defaults to today
end-before-start blocks submit
strength/form optional
network failure retains all entered values
loading blocks duplicate submit
successful submit pops to profile and invalidates medication list
profile shows Metformin, 500 mg, tablet, Draft
form contains no frequency/time/meal/reminder inputs
```

- [ ] **Step 2: Implement domain/repository**

Map server fields `id,family_member_id,medicine_master_id,display_name,strength,dosage_form,status,start_date,end_date,created_at,updated_at`. Implement the four Locked MedicationRepository methods. Create payload contains only `display_name,strength,dosage_form,start_date,end_date`.

- [ ] **Step 3: Implement route/form/profile provider**

Route:

```text
/family/:memberId/medications/new
```

Use a `FutureProvider.family<List<MemberMedication>, String>` (or equivalent Riverpod 2 family provider) for profile medicines. On successful creation invalidate the member's medication provider before popping.

- [ ] **Step 4: Add exact medication localization keys**

```text
addManually: Add manually / হাতে লিখে যোগ করুন
addMedicationManually: Add medication manually / ওষুধ হাতে লিখে যোগ করুন
medicineName: Medicine name / ওষুধের নাম
strengthLabel: Strength / শক্তি
 dosageForm: Dosage form / ওষুধের ধরন
startDate: Start date / শুরুর তারিখ
endDate: End date / শেষ তারিখ
saveMedicine: Save medicine / ওষুধ সংরক্ষণ করুন
draftStatus: Draft / খসড়া
invalidDateRange: End date cannot be before start date. / শেষের তারিখ শুরুর তারিখের আগে হতে পারে না।
```

Remove the accidental leading space before the `dosageForm` key when entering ARB JSON; the key itself is `dosageForm`.

- [ ] **Step 5: Verify + commit**

```bash
flutter gen-l10n
flutter test test/features/medications/manual_medication_flow_test.dart test/features/family/family_flow_test.dart
flutter analyze
git add mobile
git commit -m "feat: add manual medication flow"
```

---

### Task 9: Real persistence acceptance tests and merge gate

**Files:**
- Create: `backend/tests/test_vertical_slice.py`
- Create: `mobile/test/features/vertical_slice_acceptance_test.dart`
- Modify: `README.md` to document `--dart-define=FAMILYMED_API_BASE_URL=...` local override.

- [ ] **Step 1: Write backend real-PostgreSQL acceptance test**

Using the normal `client` fixture, execute exactly:

```text
POST register Sifat -> capture tokens
POST family-members Amma/mother/bn/Asia-Dhaka
GET Amma -> persisted
POST Amma medications Metformin/500 mg/tablet/start today -> status draft
POST login again -> new access token
GET /auth/me -> Sifat
GET /family-members -> contains Amma
GET /family-members/{amma}/medications -> contains Metformin
```

Assertions use real PostgreSQL rows inside the rollback-isolated test transaction; no repository fakes.

- [ ] **Step 2: Write Flutter full-flow acceptance widget test**

Override providers with in-memory fake Auth/Family/Medication repositories that implement the same Locked interfaces. Drive taps/text input through:

```text
Welcome -> Register -> care-for -> My parent -> Add Amma -> profile -> Add manually -> Metformin -> profile list -> simulated app rebuild with stored AuthState -> family list -> profile
```

This test proves routing/state/UI integration; the backend test in Step 1 separately proves real API persistence.

- [ ] **Step 3: Run complete backend gate from empty schema**

```bash
cd backend
uv run ruff check .
uv run alembic downgrade base
uv run alembic upgrade head
uv run pytest -v
```

Expected: all PASS.

- [ ] **Step 4: Run complete mobile gate**

```bash
cd ../mobile
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter build apk --debug
```

Expected: all PASS.

- [ ] **Step 5: Run explicit secret/scope searches**

```bash
cd ..
git grep -nE "print\(.*(token|password)|password_hash.*(json|response)|refresh_token.*log" -- backend mobile || true
git grep -nE "class .*Schedule|class .*Dose|flutter_local_notifications|/prescriptions/.*/extract|OCR|HTR" -- backend/app mobile/lib || true
```

Expected first command: no unsafe logging/serialization. Expected second command: no newly implemented schedule/dose/notification/OCR subsystem; existing harmless product copy/comments are reviewed manually.

- [ ] **Step 6: Update README API-base run command**

Document:

```bash
cd mobile
flutter run --dart-define=FAMILYMED_API_BASE_URL=http://10.0.2.2:8000/api/v1
```

and note that a physical device needs the development machine's reachable LAN address rather than `10.0.2.2`.

- [ ] **Step 7: Commit acceptance tests/docs**

```bash
git add backend/tests/test_vertical_slice.py mobile/test/features/vertical_slice_acceptance_test.dart README.md
git commit -m "test: verify auth family medication vertical slice"
```

- [ ] **Step 8: Push/open draft PR and use clean CI as authoritative cross-platform gate**

PR summary lists: auth + `/me`; atomic family owner creation; member APIs; manual draft medication APIs; secure mobile session/refresh gate; family/manual-medication UI; authorization tests. Wait for both backend and mobile jobs to pass.

- [ ] **Step 9: Whole-branch review before finishing workflow**

Review `main...feat/auth-family-medications` for: JWT type/expiry validation; password hash exposure; registration transaction/race; cross-family 404 behavior; single refresh future; form value preservation; draft medicine not presented as active routine; English/Bangla key parity. Resolve every blocking finding, rerun affected tests, then invoke the finishing-development-branch workflow.

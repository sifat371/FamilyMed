# FamilyMed Auth + Family + Manual Medication Slice Design

Date: 2026-09-23
Status: Approved in-chat design, pending written-spec review
Branch: `feat/auth-family-medications`

## 1. Purpose

This slice establishes the first real end-to-end FamilyMed product flow on top of the approved V1 foundation.

The goal is to let a user:

1. register or log in;
2. create and access their own family context;
3. add a family member such as Amma;
4. open that member's profile;
5. manually add a medication for that member;
6. see that medication persisted and returned from the backend.

This slice deliberately stops before medication schedules, reminders, Today dashboard logic, prescription upload, OCR/HTR, and AI verification.

## 2. Architectural approach

Implement the backend and Flutter client together as one vertical slice rather than completing one platform first.

The backend will expose authenticated APIs and persisted domain models. Flutter will use those APIs immediately, so the first feature branch ends with a working integrated flow instead of mocked production-facing screens.

The existing monorepo remains unchanged in overall structure:

```text
familymed/
├── backend/
├── mobile/
├── ai/
├── docs/
├── infra/
└── docker-compose.yml
```

The `ai/` service is not touched in this slice.

## 3. Scope

### Included

- email/password registration;
- email/password login;
- JWT access token issuance;
- refresh-token issuance and refresh endpoint;
- secure password hashing;
- authenticated backend dependency boundary;
- automatic family creation for a newly registered user;
- automatic owner membership creation;
- family-member list/create/read/update APIs;
- strict family ownership/authorization checks;
- manual member-medication list/create/read/update APIs;
- Flutter secure token storage;
- Flutter authenticated routing;
- Flutter registration and login screens;
- Flutter family-member onboarding and profile screens;
- Flutter manual medication-entry flow;
- English/Bangla localization keys for all new user-facing strings;
- backend and mobile tests for the vertical slice.

### Excluded

- password reset;
- email verification;
- social login;
- phone OTP;
- server-side refresh-token revocation/session management;
- caregiver invitations;
- multi-user family collaboration;
- medicine-master import/search UI;
- schedule creation;
- reminders;
- Today dashboard;
- dose events;
- notifications;
- prescriptions;
- OCR/HTR;
- AI extraction or confirmation.

## 4. Authentication design

### Registration

`POST /api/v1/auth/register`

Request:

```json
{
  "name": "Sifat",
  "email": "sifat@example.com",
  "password": "a-strong-password"
}
```

Registration runs in one database transaction and creates:

1. `users` row;
2. `families` row;
3. `family_memberships` row with role `owner` and status `active`.

Duplicate normalized email returns HTTP 409 with a machine-readable error code.

### Login

`POST /api/v1/auth/login`

Valid credentials return user profile data, an access token, and a refresh token.

Invalid email/password returns HTTP 401 using the same generic message so the API does not reveal whether an account exists.

### Current user

`GET /api/v1/auth/me`

Returns the authenticated user's non-sensitive profile fields. Flutter uses this when restoring a stored session and when it needs authoritative account data after relaunch.

### Token model

Use signed JWTs with explicit token type claims.

- access token: short lived, default 15 minutes;
- refresh token: default 30 days;
- both contain the authenticated user UUID as `sub`;
- access token contains `type=access`;
- refresh token contains `type=refresh`.

`POST /api/v1/auth/refresh` accepts a valid refresh token and returns a new access token. The stored refresh token remains valid until its own expiry in this slice.

Server-side refresh-token storage, revocation, and true rotation are intentionally deferred. The public API can later add those protections without changing the mobile login flow.

### Password storage

Use a modern adaptive password hash through a maintained password-hashing library. Passwords are never logged or stored in plaintext.

The backend should use Argon2 through the selected maintained library.

### Authenticated request dependency

Protected routes resolve the current user from the bearer access token.

Invalid, expired, malformed, wrong-type, or unknown-user tokens return HTTP 401.

Authorization is separate from authentication: resolving a user does not automatically grant access to any supplied family/member/medication UUID.

### Authentication validation

- name: trimmed, 1-120 characters;
- email: syntactically valid, trimmed and lowercased before lookup/persistence;
- password: 8-128 characters in this slice;
- no password-complexity rule beyond minimum length; the UI may encourage a stronger password but must not invent a backend rule.

## 5. User and family data model

### `users`

Required fields for this slice:

- `id UUID PK`
- `name VARCHAR(120)`
- `email VARCHAR(255) UNIQUE`
- `password_hash TEXT`
- `preferred_language VARCHAR(5)` default `en`
- `timezone VARCHAR(64)` default `Asia/Dhaka`
- `created_at TIMESTAMPTZ`
- `updated_at TIMESTAMPTZ`

Emails are normalized to trimmed lowercase before uniqueness checks and persistence.

### `families`

- `id UUID PK`
- `name VARCHAR(160)`
- `created_by_user_id UUID FK users.id`
- `created_at TIMESTAMPTZ`
- `updated_at TIMESTAMPTZ`

Default family name for registration is `<user name>'s family`.

### `family_memberships`

- `id UUID PK`
- `family_id UUID FK families.id`
- `user_id UUID FK users.id`
- `role` enum/string: `owner`, `caregiver`, `viewer`
- `status` enum/string: `active`, `pending`, `revoked`
- `created_at TIMESTAMPTZ`

V1 creates only `owner/active` memberships.

A unique constraint prevents duplicate `(family_id, user_id)` memberships.

## 6. Family-member model

### `family_members`

- `id UUID PK`
- `family_id UUID FK families.id`
- `name VARCHAR(120)`
- `relationship VARCHAR(40)`
- `date_of_birth DATE NULL`
- `preferred_language VARCHAR(5)`
- `linked_user_id UUID NULL`
- `profile_image_key TEXT NULL`
- `timezone VARCHAR(64)` default `Asia/Dhaka`
- `created_at TIMESTAMPTZ`
- `updated_at TIMESTAMPTZ`
- `archived_at TIMESTAMPTZ NULL`

No NID, address, diagnosis, hospital, or other unnecessary health/profile fields are added.

Archived members are excluded from normal list responses but their future historical data model remains preservable.

Family-member validation:

- name: trimmed, 1-120 characters;
- relationship: trimmed, 1-40 characters;
- preferred language: `en` or `bn`;
- date of birth: optional and cannot be in the future;
- timezone: valid IANA timezone string; Flutter defaults new members to `Asia/Dhaka` for the Bangladesh-first V1.

The approved Amma onboarding preselects Bangla on the client, but the backend does not silently infer language from relationship.

## 7. Medication model for this slice

### `medicine_master`

Create the table now to preserve the approved V1 schema boundary, but do not import a catalog in this slice.

Fields:

- `id UUID PK`
- `brand_name VARCHAR(160) NULL`
- `generic_name VARCHAR(160)`
- `strength VARCHAR(80) NULL`
- `dosage_form VARCHAR(80) NULL`
- `manufacturer VARCHAR(160) NULL`
- `country VARCHAR(2)`
- `source VARCHAR(120)`
- `source_reference TEXT NULL`
- `normalized_search_text TEXT`
- `active BOOLEAN` default true
- `created_at TIMESTAMPTZ`
- `updated_at TIMESTAMPTZ`

### `member_medications`

A row means a specific family member is taking or preparing to take a medicine.

Fields:

- `id UUID PK`
- `family_member_id UUID FK family_members.id`
- `medicine_master_id UUID NULL FK medicine_master.id`
- `prescription_id UUID NULL` reserved for a later migration that will add the prescription foreign key;
- `extraction_id UUID NULL` reserved for a later migration that will add the extraction foreign key;
- `display_name VARCHAR(180)`
- `strength VARCHAR(80) NULL`
- `dosage_form VARCHAR(80) NULL`
- `status` enum/string
- `start_date DATE`
- `end_date DATE NULL`
- `created_by_user_id UUID FK users.id`
- `created_at TIMESTAMPTZ`
- `updated_at TIMESTAMPTZ`

Manual medicines use `medicine_master_id = NULL`.

Medication states available in the schema:

- `draft`
- `active`
- `paused`
- `completed`
- `ended`

This slice creates manually entered medicines as `draft`. Activation will happen when schedule/routine creation is implemented in the next medication-routine slice.

No hard-delete endpoint is added.

Medication validation:

- display name: trimmed, 1-180 characters;
- strength: optional, trimmed, max 80 characters;
- dosage form: optional, trimmed, max 80 characters;
- start date: required;
- end date: optional and must be on or after start date.

## 8. Authorization rules

Every protected family/member/medication operation must derive authorization from the authenticated user's membership.

The required ownership chain is:

```text
authenticated user
  -> active family membership
  -> family
  -> family member
  -> member medication
```

A client-supplied UUID is never sufficient authorization by itself.

For V1, any active membership role may read resources, but only `owner` and `caregiver` are structurally allowed to mutate. Because only `owner` exists in this slice, the exposed behavior is effectively owner-only mutation.

Requests for resources outside the user's accessible family return 404 rather than revealing cross-family resource existence.

## 9. API contract

Base path: `/api/v1`.

### Authentication

- `POST /auth/register`
- `POST /auth/login`
- `POST /auth/refresh`
- `GET /auth/me`

### Family members

- `GET /family-members`
- `POST /family-members`
- `GET /family-members/{member_id}`
- `PATCH /family-members/{member_id}`

`GET /family-members` returns non-archived members from families where the current user has an active membership.

### Member medications

- `GET /family-members/{member_id}/medications`
- `POST /family-members/{member_id}/medications`
- `GET /member-medications/{medication_id}`
- `PATCH /member-medications/{medication_id}`

For this slice, medication PATCH may update:

- display name;
- strength;
- dosage form;
- start date;
- end date.

Status lifecycle actions are deferred to their dedicated future endpoints rather than allowing arbitrary client status strings through PATCH.

### Standard errors

Use the approved envelope:

```json
{
  "error": {
    "code": "MACHINE_READABLE_CODE",
    "message": "Human-readable message",
    "details": {}
  }
}
```

Expected codes include:

- `EMAIL_ALREADY_REGISTERED`
- `INVALID_CREDENTIALS`
- `INVALID_TOKEN`
- `FAMILY_MEMBER_NOT_FOUND`
- `MEDICATION_NOT_FOUND`
- `VALIDATION_ERROR`

FastAPI/Pydantic validation errors must also be adapted to this envelope rather than leaking the framework's default error shape to the mobile client.

## 10. Backend module structure

Extend the existing FastAPI project into feature domains:

```text
backend/app/
├── auth/
│   ├── router.py
│   ├── schemas.py
│   ├── service.py
│   └── security.py
├── users/
│   └── models.py
├── families/
│   ├── models.py
│   ├── router.py
│   ├── schemas.py
│   ├── service.py
│   └── repository.py
├── medications/
│   ├── models.py
│   ├── router.py
│   ├── schemas.py
│   ├── service.py
│   └── repository.py
├── common/
│   ├── errors.py
│   └── auth.py
├── api/
├── config.py
├── db.py
└── main.py
```

Domain models should remain isolated enough that later schedule and prescription slices can attach without moving these responsibilities again.

## 11. Flutter architecture

Add the following dependencies:

- `flutter_riverpod` for application state and dependency injection;
- Dio for HTTP calls;
- `flutter_secure_storage` for access/refresh token storage.

Keep the existing feature-first structure:

```text
mobile/lib/
├── app/
│   ├── app.dart
│   └── router.dart
├── core/
│   ├── api/
│   ├── auth/
│   ├── storage/
│   ├── database/
│   ├── localization/
│   └── theme/
└── features/
    ├── auth/
    ├── family/
    └── medications/
```

### Token handling

- access and refresh tokens are stored in secure storage;
- the API client adds the bearer access token to protected requests;
- one automatic access-token refresh attempt is allowed after a 401 caused by an expired access token;
- concurrent refresh attempts share one in-flight refresh operation rather than triggering multiple refresh requests;
- successful refresh replaces the stored access token while keeping the existing refresh token;
- refresh failure clears local auth state and routes to login.

### Auth routing

App launch resolves stored auth state before choosing the initial route.

- no stored refresh token -> Welcome/Login/Register flow;
- stored session -> call `/auth/me`, refreshing the access token once if required;
- unrecoverable session validation failure -> clear tokens and show login;
- registration success with zero family members -> `Who do you care for?` / add-member flow;
- authenticated user with one or more members -> `/family`, a simple family-member list screen;
- selecting a member from `/family` -> family-member profile.

The exact broader Today-navigation shell remains deferred until the dashboard slice.

## 12. Flutter UX for this slice

### Welcome

Use the approved FamilyMed teal/cream visual system and existing Welcome screen as the entry point.

Add clear actions for:

- `Get started` -> registration;
- `I already have an account` -> login.

### Registration

Fields:

- name;
- email;
- password.

After success, continue directly into the care relationship / add-family-member flow.

### Login

Fields:

- email;
- password.

After success:

- zero members -> add-member flow;
- existing members -> `/family` member list.

### Family onboarding

Preserve the approved screens:

1. Who do you care for?
2. Add family member.

The relationship choice pre-fills the relationship field but remains editable.

### Family list

This slice adds a minimal authenticated `/family` screen for returning users.

It shows the current user's family-member cards and an `Add family member` action. Tapping a card opens that member's profile.

### Family-member profile

Show:

- member name;
- relationship;
- language summary;
- current medication list;
- empty state when no medications exist;
- disabled `Scan prescription — coming soon` action to preserve the approved hierarchy without suggesting that scanning already works;
- active `Add manually` action.

The implemented behavior in this slice is manual entry only.

### Manual medication entry

Fields:

- medicine name required;
- strength optional;
- dosage form optional;
- start date required, default today;
- end date optional.

Submitting creates a `draft` member medication and returns to the member profile where the new medicine is listed.

No dose, frequency, clock time, meal relation, or reminder fields appear yet. Those belong to schedule creation, not medication identity.

## 13. Localization and accessibility

All new user-facing strings must use localization resources.

English and Bangla resource keys are added together in this slice.

UI requirements:

- primary touch targets approximately 44-48 px minimum;
- medicine/member text must remain readable with larger system text;
- validation errors are shown in text, not color alone;
- primary actions use plain language;
- form labels are explicit and persist when a field contains text.

## 14. Error handling

### Backend

- validation errors use the standard error envelope;
- duplicate email is 409;
- bad credentials are 401;
- invalid/expired auth is 401;
- inaccessible family/member/medication resources are 404;
- unexpected DB errors are not returned with raw SQL or stack traces.

### Flutter

- form validation catches obvious required-field problems before network submission;
- backend field/general errors remain visible and retryable;
- network failure does not discard user-entered form values;
- refresh-token failure returns the user to login cleanly;
- loading state prevents duplicate create submissions.

Offline creation/synchronization of family members and medicines is not implemented in this slice. That broader offline sync mechanism remains part of the approved V1 but will be introduced with the sync-focused slice.

## 15. Database migration

Create one forward migration after `0001_bootstrap` that introduces:

- users;
- families;
- family_memberships;
- family_members;
- medicine_master;
- member_medications;
- required indexes and uniqueness constraints.

`prescription_id` and `extraction_id` are nullable UUID columns only in this migration because their target tables do not yet exist. Later prescription/extraction migrations will add the foreign-key constraints.

Alembic metadata must include all new SQLAlchemy models so later autogeneration remains reliable.

Migration CI must upgrade from an empty PostgreSQL database to head successfully.

## 16. Testing strategy

### Backend tests

Authentication:

- registration creates user, family, and owner membership;
- email normalization works;
- duplicate email rejected;
- password is hashed, not stored plaintext;
- valid login succeeds;
- wrong password rejected;
- unknown email rejected with generic invalid-credentials behavior;
- valid refresh returns a new access token;
- access token cannot be used as refresh token;
- refresh token cannot be used as bearer access token;
- `/auth/me` returns the authenticated user's safe profile;
- protected route without access token rejected.

Authorization:

- user A cannot read user B's family member;
- user A cannot edit user B's family member;
- user A cannot list/create/read/edit medications under user B's member.

Family:

- create member persists expected fields;
- future DOB rejected;
- list returns current user's non-archived members;
- update persists allowed changes.

Medication:

- manual medication persists with `medicine_master_id = NULL`;
- manual medication starts as `draft`;
- end date before start date rejected;
- medication list is scoped to the requested authorized member;
- update persists allowed identity/date changes.

### Flutter tests

- unauthenticated router shows auth flow;
- successful registration stores tokens and advances to family onboarding;
- successful login with no members advances to add-member flow;
- successful login with members advances to `/family`;
- failed login displays error without clearing email field;
- add-member form validates and submits;
- family-member profile empty medication state renders;
- scan-prescription action is visibly disabled/coming soon;
- manual-medication form validates and submits;
- created medication appears on member profile after state refresh;
- auth refresh failure clears the session;
- localization smoke test covers English and Bangla resources for new screens.

### Branch verification

The feature branch is mergeable only after all of the following pass:

Backend:

```text
uv sync --all-groups
uv run ruff check .
uv run alembic upgrade head
uv run pytest -v
```

Mobile:

```text
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter build apk --debug
```

## 17. Acceptance flow

The slice is complete when this real backend/mobile flow works:

```text
Open app
-> Register with name/email/password
-> Auth tokens stored securely
-> User family + owner membership created server-side
-> Choose "My parent"
-> Add "Amma" / Mother / Bangla
-> Amma profile appears with no medicines
-> Choose Add manually
-> Add "Metformin" / "500 mg" / tablet
-> Backend creates draft member medication
-> Return to Amma profile
-> Metformin 500 mg appears in Amma's medication list
-> Relaunch/login again
-> /auth/me restores the account session
-> /family loads Amma
-> Amma profile loads Metformin from persisted backend data
```

This acceptance flow does not require a schedule or reminder.

## 18. Security boundaries

- passwords never leave TLS-protected production traffic except as request body input and are immediately hashed server-side;
- password hashes never return through API schemas;
- access/refresh tokens are never written to normal application logs;
- Flutter uses secure storage rather than Drift/SharedPreferences for tokens;
- authorization is checked server-side on every family/member/medication resource;
- API responses do not reveal cross-family resource existence;
- no prescription or research-data concerns are introduced in this slice.

## 19. Deferred follow-up

The next product slice after this one should add medication routine/schedule creation, then dose generation/Today/reminders in subsequent focused cycles.

This branch must not implement those future domains early merely because the database or UI could support them.
# FamilyMed V1 Design Specification

Date: 2026-09-22
Status: Approved product design, pending implementation-plan review

## 1. Product definition

FamilyMed is a family medication-care application. It helps one account holder organize medication routines for themselves and people they care for, such as parents, spouse, children, or other family members.

The V1 product loop is:

1. Add a family member.
2. Add a medicine manually or from a prescription image.
3. If a prescription is used, AI proposes medicine candidates.
4. A human reviews and confirms each medicine.
5. The user configures reminder times for the confirmed medication schedule.
6. The app creates dose events and reminders.
7. The user or caregiver marks doses taken, snoozed, skipped, or missed.
8. The Today dashboard and history show family medication status.

Family care is the product. Prescription AI is an assistant inside the product, not the product itself.

## 2. V1 goals

V1 must let a single registered user reliably manage medication routines for multiple family members while keeping the prescription workflow safe and understandable.

Success means the following golden path works end to end:

- register/login;
- add Amma as a family member;
- upload a prescription;
- receive two mocked or real extraction results;
- confirm Metformin 500 mg;
- select and explicitly confirm Amlodipine 5 mg;
- configure Metformin as morning + night and Amlodipine as morning;
- enable reminders;
- show 3 scheduled doses on Today;
- mark two doses taken;
- show `2/3 taken` on the dashboard;
- preserve the actions in history.

## 3. V1 scope

### Included

- email/password authentication;
- one user account managing multiple family members;
- family member profiles;
- manual medicine entry;
- medicine search against a master medicine table;
- prescription photo upload;
- AI extraction service interface;
- mocked extraction implementation before real OCR/HTR integration;
- human candidate selection and explicit confirmation;
- medication schedule creation;
- reminder-time configuration;
- local notifications;
- Today dashboard;
- dose actions: taken, snooze, skip;
- missed-dose transition;
- medication and dose history;
- prescription history;
- English/Bangla localization architecture;
- offline local cache and queued dose-action sync;
- secure object storage abstraction for prescription images.

### Excluded from V1

- multiple caregiver accounts and invitations;
- doctor accounts;
- pharmacy ordering;
- hospital/EHR integration;
- pill-image identification;
- diagnosis;
- medication recommendation;
- dose recommendation;
- drug substitution;
- drug-interaction decisions;
- emergency triage;
- insurance;
- automatic research-data collection;
- advanced refill prediction.

The database may contain future-facing fields for caregiver sharing, but no multi-caregiver UI or workflow will be implemented in V1.

## 4. Safety rules

These rules apply across UI, backend, database, and AI services.

1. AI cannot prescribe.
2. AI cannot change a prescribed dose.
3. AI extraction cannot create an active medication directly.
4. `selected` and `confirmed` are separate extraction states.
5. Unknown or unreadable text remains unknown; the system must not guess silently.
6. The original prescription image or crop remains available during confirmation.
7. Users can manually correct AI output.
8. Prescription instructions and reminder clock times are separate concepts.
9. `1+0+1` describes dose periods; it does not imply specific clock times such as 08:00 and 20:00.
10. `taken` means a user/caregiver marked the dose as taken; it does not prove ingestion.
11. Editing a schedule affects future dose events only.
12. Ending a medication does not delete historical doses or logs.

## 5. Technology architecture

FamilyMed will use a monorepo:

```text
familymed/
├── mobile/      # Flutter application
├── backend/     # FastAPI application
├── ai/          # Prescription extraction service; mocked first
├── docs/
├── infra/
└── docker-compose.yml
```

### Mobile

- Flutter
- feature-first folder structure
- Drift/SQLite for local medication and dose state
- secure storage for authentication tokens
- Flutter localization with English and Bangla resources
- local notification scheduling
- background/queued synchronization when connectivity returns

### Backend

- FastAPI
- PostgreSQL
- SQLAlchemy 2.x
- Alembic migrations
- Pydantic schemas
- JWT access/refresh authentication
- password hashing with a modern password-hashing library
- service/repository separation for domain logic

### AI service

- separate internal service boundary;
- mocked JSON implementation first;
- later replaceable by OCR/HTR + medicine retrieval + confidence calibration;
- no permission to create medications or schedules.

### Storage

- prescription binaries are not stored in PostgreSQL;
- backend stores `storage_key` metadata;
- development may use local/S3-compatible storage;
- production target is S3-compatible object storage with non-public access.

## 6. Main domain model

### User and family

- `users`
- `families`
- `family_memberships`
- `family_members`

V1 automatically creates or associates a family for the account owner. Only the owner role is exposed in V1.

### Prescription and extraction

- `prescriptions`
- `prescription_extractions`
- `extraction_candidates`

Prescription state:

`uploaded -> processing -> needs_review -> verified`

Failure path:

`uploaded|processing -> failed`

Extraction state:

`suggested -> selected -> confirmed`

Alternative terminal states:

`corrected`, `rejected`

`selected` must never be treated as `confirmed`.

### Medicines

- `medicine_master`
- `member_medications`

`medicine_master` contains canonical searchable medicine data.

`member_medications` means a specific family member is taking a medicine. `medicine_master_id` is nullable so manual custom medicines are supported.

Medication state:

`draft -> active -> paused -> active`

Terminal states:

`completed`, `ended`

### Schedules and doses

- `medication_schedules`
- `schedule_times`
- `scheduled_doses`
- `dose_logs`

A schedule preserves the raw prescription instruction separately from reminder times.

Example:

```text
raw_instruction = "1+0+1 PC"
meal_relation = after_food
schedule_times = [08:00 morning, 20:00 night]
```

The clock times are user reminder preferences, not prescription content.

Dose state:

`upcoming -> pending -> taken`

or

`upcoming -> pending -> skipped`

or

`upcoming -> pending -> missed`

Snooze keeps the dose in `pending` and sets `snoozed_until`.

`dose_logs` is an immutable event history of user/system actions.

## 7. Core database fields

All primary keys use UUIDs. Database timestamps use UTC. Family members and schedules store an IANA timezone such as `Asia/Dhaka` for local display and scheduling.

### users

- id
- name
- email unique
- password_hash
- preferred_language
- timezone
- created_at
- updated_at

### family_members

- id
- family_id
- name
- relationship
- date_of_birth nullable
- preferred_language
- linked_user_id nullable
- profile_image_key nullable
- timezone
- created_at
- updated_at
- archived_at nullable

### prescriptions

- id
- family_member_id
- storage_key
- original_filename
- prescription_date nullable
- doctor_name nullable
- facility_name nullable
- status
- created_by_user_id
- created_at
- updated_at

### prescription_extractions

- id
- prescription_id
- crop_storage_key nullable
- raw_ocr_text
- confidence nullable
- status
- selected_candidate_id nullable
- confirmed_text nullable
- confirmed_by_user_id nullable
- confirmed_at nullable
- created_at

### extraction_candidates

- id
- extraction_id
- medicine_master_id nullable
- candidate_name
- candidate_strength nullable
- candidate_form nullable
- score nullable
- rank
- created_at

### medicine_master

- id
- brand_name nullable
- generic_name
- strength nullable
- dosage_form nullable
- manufacturer nullable
- country
- source
- source_reference nullable
- normalized_search_text
- active
- created_at
- updated_at

### member_medications

- id
- family_member_id
- medicine_master_id nullable
- prescription_id nullable
- extraction_id nullable
- display_name
- strength nullable
- dosage_form nullable
- status
- start_date
- end_date nullable
- created_by_user_id
- created_at
- updated_at

### medication_schedules

- id
- member_medication_id
- raw_instruction nullable
- meal_relation
- timezone
- start_date
- end_date nullable
- status
- created_at
- updated_at

### schedule_times

- id
- schedule_id
- period
- local_time
- quantity
- unit
- sort_order

### scheduled_doses

- id
- schedule_id
- family_member_id
- member_medication_id
- scheduled_at
- status
- taken_at nullable
- skipped_at nullable
- missed_at nullable
- snoozed_until nullable
- created_at
- updated_at

### dose_logs

- id
- scheduled_dose_id
- action
- performed_by_user_id nullable
- occurred_at
- metadata JSONB

### notification_preferences

- id
- family_member_id
- user_id
- enabled
- default_snooze_minutes (V1 default: 15)
- caregiver_escalation_enabled (false in V1)
- created_at
- updated_at

## 8. API contract

Base path: `/api/v1`

### Authentication

- `POST /auth/register`
- `POST /auth/login`
- `POST /auth/refresh`

### Family members

- `GET /family-members`
- `POST /family-members`
- `GET /family-members/{member_id}`
- `PATCH /family-members/{member_id}`

### Prescriptions

- `POST /family-members/{member_id}/prescriptions`
- `POST /prescriptions/{prescription_id}/extract`
- `GET /prescriptions/{prescription_id}/extractions`
- `GET /family-members/{member_id}/prescriptions`
- `GET /prescriptions/{prescription_id}`

### Extraction verification

- `POST /extractions/{extraction_id}/select`
- `POST /extractions/{extraction_id}/confirm`

Selection changes the extraction to `selected`. Confirmation is a separate request and changes it to `confirmed` or `corrected`.

### Medicines and schedules

- `GET /medicines/search?q=...`
- `POST /family-members/{member_id}/medications`
- `POST /member-medications/{medication_id}/schedules`
- `PATCH /schedules/{schedule_id}`
- `POST /member-medications/{id}/pause`
- `POST /member-medications/{id}/resume`
- `POST /member-medications/{id}/end`

### Dashboard and dose actions

- `GET /today`
- `POST /doses/{dose_id}/taken`
- `POST /doses/{dose_id}/snooze`
- `POST /doses/{dose_id}/skip`
- `POST /doses/{dose_id}/correct`
- `GET /family-members/{member_id}/history`

Standard API errors use:

```json
{
  "error": {
    "code": "MACHINE_READABLE_CODE",
    "message": "Human-readable message",
    "details": {}
  }
}
```

## 9. Today endpoint

`GET /api/v1/today` is an application-oriented aggregate endpoint. Flutter should not need to join raw medication and schedule objects to render the home screen.

It returns family members, per-person summary counts, and the day's doses.

For the approved golden path, Amma has:

- Metformin 500 mg at 08:00 — taken
- Amlodipine 5 mg at 08:00 — taken
- Metformin 500 mg at 20:00 — upcoming/pending

The resulting summary is `2/3 taken`.

## 10. Dose generation

The backend generates dose events in a rolling 30-day window.

Generation runs when:

- a schedule is created;
- a schedule is edited;
- an application maintenance task replenishes the future window.

Past doses are never regenerated or rewritten because a future schedule changes.

## 11. Offline-first behavior

The mobile application caches:

- family members;
- active medications;
- schedules;
- schedule times;
- scheduled doses;
- local dose logs.

Dose actions are optimistic locally.

If a user marks a dose taken without network connectivity:

1. local dose state becomes `taken` immediately;
2. a `SyncOperation` is queued;
3. the UI updates immediately;
4. when connectivity returns, the action is posted to the backend;
5. successful synchronization clears the queued operation.

OCR/extraction may require network connectivity in V1.

## 12. Notifications

V1 uses local device notifications for dose reminders.

Rules:

- notification permission is requested only after routines exist;
- declining notification permission does not deactivate routines;
- default snooze is 15 minutes;
- snooze does not alter the underlying schedule;
- notification schedules are recalculated when medication schedules change;
- the app remains usable when permission is denied.

## 13. Localization and accessibility

Localization infrastructure is included from the first Flutter commit.

Use English and Bangla resource keys rather than hard-coded user-facing strings.

Accessibility requirements:

- primary touch targets approximately 44–48 px minimum;
- operational medicine text at least approximately 14–15 px;
- status must not depend on color alone;
- layouts should tolerate larger system text reasonably;
- important actions use plain language;
- the elder-focused simplified interface is deferred beyond V1 but the visual system must not block it.

## 14. Security and privacy

- production traffic uses HTTPS;
- passwords are hashed, never stored in plaintext;
- access and refresh tokens are stored securely on-device;
- every family-member resource request verifies authenticated family membership;
- prescription objects are private and not exposed through permanent public URLs;
- backend logs should avoid prescription content and sensitive medicine details unless required for debugging;
- AI processing receives only the minimum required prescription image/reference;
- AI extraction data is not silently repurposed as a research dataset;
- research reuse would require a separate consent and anonymization process.

## 15. Error behavior

V1 must handle these states explicitly:

- no internet;
- upload failure;
- extraction failure;
- unreadable prescription;
- no medicine candidate match;
- manual medicine not found in master database;
- notification permission denied;
- backend unavailable;
- invalid schedule;
- duplicate action submission;
- sync retry/failure.

The user must always retain a manual path for medicine entry when AI or medicine search fails.

## 16. Testing strategy

### Backend

- unit tests for state transitions and domain services;
- API tests for authentication, family ownership, prescriptions, confirmation, schedules, and dose actions;
- authorization tests proving users cannot access another family's resources;
- migration tests against PostgreSQL in CI.

### Mobile

- unit tests for local repositories and sync behavior;
- widget tests for safety-critical review and dose-action states;
- notification scheduling tests where supported;
- integration test for the golden path using mocked API/extraction responses.

### Golden-path acceptance test

1. Register.
2. Add Amma.
3. Upload prescription.
4. Mock extraction returns Metformin and Amlodipine candidates.
5. Confirm Metformin.
6. Select Amlodipine 5 mg; verify it is still pending confirmation.
7. Explicitly confirm Amlodipine.
8. Configure reminder times.
9. Enable reminders or choose Not now without disabling routines.
10. Today shows 3 doses.
11. Mark two doses taken.
12. Today displays `2/3 taken`.
13. History contains the two marked-taken actions.

## 17. Development order

Implementation should proceed in this order:

1. repository and development-environment scaffolding;
2. FastAPI health/config/database foundation;
3. Flutter application shell, theme, localization, routing, local database;
4. authentication;
5. family-member flow;
6. manual medicine entry and schedules;
7. scheduled-dose generation;
8. Today dashboard and dose actions;
9. local notifications;
10. history;
11. backend/mobile synchronization;
12. prescription upload;
13. mocked extraction API;
14. human verification UI;
15. real OCR/HTR service integration.

Real OCR must not block development of the core medication-care product.

## 18. Repository quality rules

- development work should normally occur on feature branches and enter `main` through pull requests;
- secrets and `.env` files are not committed;
- `.env.example` documents required configuration;
- schema changes use migrations;
- backend formatting/linting/tests and Flutter formatting/analyze/tests are automated in CI;
- no product-code change is considered complete without relevant tests;
- Figma `V1.1 — Revised Golden Path` is the visual reference for the implemented golden path.

## 19. Definition of V1 complete

V1 is complete when the approved golden path works on an Android development build with the FastAPI/PostgreSQL backend, including offline-capable dose logging and local reminders, while prescription extraction may still use the mock AI adapter.

A real prescription-recognition model is a subsequent milestone built behind the already-defined extraction interface.

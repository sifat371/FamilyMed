# FamilyMed V1 — fastest safe Android release

## Free beta deployment: Render Free + Neon Free

**Use synthetic demo data only.** Free instances can sleep, be suspended at monthly quotas, and cannot guarantee availability for medication reminders. This is not a suitable service for patient reliance.

The root `render.yaml` uses **only one Render Free web service**; it does not create any Render PostgreSQL resource, paid or free. Its database is an external persistent Neon Free project, with separate storage. This avoids Render's 30-day free-Postgres expiry.

1. Create a **Neon Free** PostgreSQL project in a region close to Render Singapore (choose a provider region actually offered by your Neon project). Do not create a paid project. Use the **direct (unpooled) TLS connection string** for Alembic migrations and runtime V1. Copy the value privately; NEVER paste it in chat or commit it to GitHub.
2. Open [Render Dashboard](https://dashboard.render.com/), connect GitHub, and import `render.yaml` from `main` into a Free Blueprint, or provision `familymed-beta-api` as a Free Docker web service with Dockerfile `backend/Dockerfile` and context `backend`.
3. Enter `FAMILYMED_DATABASE_URL` privately in the Render UI using Neon's PostgreSQL connection string with `?sslmode=require` (Neon's URL may also include `channel_binding=require`). The backend translates these libpq parameters for asyncpg, while migrations use psycopg3.
4. Set `FAMILYMED_SUPPORT_EMAIL` to an **owner-approved public inbox**. The Render Blueprint generates a private strong `FAMILYMED_JWT_SECRET`. Keep secrets out of chat, screenshots, logs, and GitHub.
5. Confirm that the Render service is using the **Free** plan and Neon project is **Free**. Render may still charge overages on paid-on-file accounts; set workspace billing alerts and review included quotas.
6. Wait for the first build to finish. Visit **the actual Render service URL** `https://<actual-host>.onrender.com/api/v1/ready` and confirm `{"status":"ready"}`. Then check public `/privacy` and `/account-deletion` routes.
7. Register ONLY a fictional beta user and medication to test persistence, schedule and history. Free sleeping services may take about one minute to wake. Verify one post-restart persistence cycle and investigate error logs before distributing.
8. After service URL is verified, rebuild Android using `--dart-define=FAMILYMED_API_BASE_URL=https://<actual-host>.onrender.com/api/v1`. The previously installed lab-PC/Tailscale APK is a different configuration and remains unchanged.
9. **Do not publish for actual medication management** until hosting availability, backups/restore, monitoring, privacy retention, abuse protection and deletion paths are reviewed.

Official caveats: https://render.com/docs/free and https://neon.com/pricing.

**Original paid production runbook** (below) describes an eventual upgrade path and is not an instruction to provision paid services today.

Status: repository preparation only. A successful PR CI run is not a public deployment or a Play Store approval.

## 1. Integration and release candidate

1. Review/merge stacked PRs **#9 → #10 → #11 → #12 → #13 → release-hardening PR** in dependency order. Recheck the base/head and CI of each PR before merging.
2. Run all GitHub Actions against integrated `main`. Preserve the old private test environment and its data.
3. Keep production PostgreSQL **separate** from lab-PC `familymed_qa` and other Docker containers. Do not copy synthetic QA accounts into production.
4. Finalize package identifier `com.familymed.familymed` **before** first Play Store registration (Google Play package names are permanent).

## 2. Render deployment (requires owner authorization/payment)

`render.yaml` defines a single paid Docker FastAPI web service and PostgreSQL 17 in Singapore. The free PostgreSQL tier expires after 30 days and is **not** a viable production database. A paid service and database incur recurring charges; confirm current prices and set spending alerts in Render before accepting.

1. Connect the owner's GitHub repository to Render. Import the root `render.yaml` as a Blueprint **only after it lands on main**.
2. Review the billed web and PostgreSQL plans, region, and available backup/storage settings before approving service creation.
3. Render generates a strong `FAMILYMED_JWT_SECRET` and injects private `FAMILYMED_DATABASE_URL` automatically. Keep both secret, never put them in commits or chats.
4. The Docker image installs locked Python 3.13 dependencies, starts Alembic migrations, then binds FastAPI to Render's `PORT`. If migration fails, the API should not begin accepting traffic. V1 assumes **one API instance**. Do not scale multiple instances before separating migrations from startup.
5. Verify `https://<actual-service>.onrender.com/api/v1/health` and `.../api/v1/ready` return success. Copy **the actual assigned Render hostname**, never guess it.
6. Check application logs, account registration/login using synthetic data, medication and reminder flows, and database persistence after deploy/restart. Ensure backup and restore procedures have been rehearsed before storing real patient information.
7. Consider custom domain, billing alerts, uptime alerts, database backups and retention. Do not put production data on Render free Postgres.

Native Flutter requests do not require browser CORS. The Blueprint sets `FAMILYMED_CORS_ORIGINS` to empty for V1.

## 3. Android Play signing and AAB

**Never use the debug APK as a Play Store release.** It is signed with the debug key and points to the private Tailscale QA API.

On a trusted owner-controlled machine, generate and securely back up an Android **upload key** (do not commit it or share its password):

```bash
keytool -genkeypair -v -keystore "$HOME/familymed-upload.jks" \
  -storetype PKCS12 -keyalg RSA -keysize 3072 -validity 10000 -alias upload
```

Create a private `mobile/android/key.properties` (already gitignored) referencing the real absolute keystore path:

```properties
storePassword=YOUR_PRIVATE_STORE_PASSWORD
keyPassword=YOUR_PRIVATE_KEY_PASSWORD
keyAlias=upload
storeFile=/absolute/path/to/familymed-upload.jks
```

Once the public API URL has been verified, run in `mobile/`:

```bash
flutter pub get
flutter gen-l10n
dart run build_runner build
flutter analyze
flutter test
flutter build appbundle --release \
  --dart-define="FAMILYMED_API_BASE_URL=https://<VERIFIED-PUBLIC-HOST>/api/v1"
```

AAB output: `mobile/build/app/outputs/bundle/release/app-release.aab`. Verify the AAB upload signing certificate before upload. Use Google **Play App Signing** and securely back up the upload key and passwords. The existing local debug APK generally cannot be updated in place by an app with a different signing key; install the Play/internal-test build as a separate transition **only after safely exporting any desired QA data**.

The Android package ID and version code must be acceptable to the chosen Play Console application. Increment `mobile/pubspec.yaml` version code for subsequent uploads.

## 4. Play Console

1. Owner/cousin must grant appropriate app-level Play Console access; do **not** exchange passwords. We cannot assume the Play Console is already connected.
2. Create the app in Play Console and configure package, countries, contact/support details, content rating, store screenshots, app icon, and signed AAB.
3. Complete **Health apps declaration**, **Data safety**, public privacy policy, permission disclosures, and account-deletion paths (both in-app and web). Do not claim AI diagnosis: V1 is a caregiver record/reminder tool.
4. Validate exact alarm / notification permissions and Google's applicable declarations. Use only permissions needed for actual functionality.
5. **Internal testing** is the quickest Play-distributed track. Whether production can launch immediately depends on the age/type of Play Console account and Play review. New personal accounts created after Nov 13, 2023 must usually complete a closed test with **12 opted-in testers for 14 continuous days** before applying for production access.
6. Verify installed release AAB **against the public backend** on a real device; debug testing against Tailscale is not a substitute for release verification.

## 5. Blocking release checks

- [ ] Release-hardening PR merged, main CI green, production image built.
- [ ] Render (or equivalent) project connected and paid plan approved; public HTTPS /ready verified.
- [ ] Database backup and restore verified; alarms/reminders rechecked against **production** API.
- [ ] Upload key created and backed up; release AAB actually signed with **upload key** (not debug).
- [ ] Privacy policy URL available publicly; health and data safety declarations accurate.
- [ ] In-app **and web** account-deletion request mechanisms usable; deletion handling documented/tested.
- [ ] Owner support email, privacy contact, data-retention policy confirmed.
- [ ] Play Console app identity and account type confirmed; test track launched.
- [ ] No unreviewed changes merged/deployed; no test credentials embedded in build.

Official references:
- https://render.com/docs/blueprint-spec
- https://docs.flutter.dev/deployment/android
- https://support.google.com/googleplay/android-developer/answer/14151465
- https://support.google.com/googleplay/android-developer/answer/13327111
- https://support.google.com/googleplay/android-developer/answer/16679511

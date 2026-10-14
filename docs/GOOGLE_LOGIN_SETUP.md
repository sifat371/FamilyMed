# FamilyMed — Google Sign-In setup and release handoff

**Work branch:** `feat/google-sign-in-v1`. Never merge/deploy before CI, real-device OAuth verification, and updated dependency lockfiles.

## Why this approach

Google ID tokens are obtained from Flutter using `google_sign_in`, sent to
`POST /api/v1/auth/google`, and verified against Google's signing keys by FastAPI.
After verification, FamilyMed issues its **own** existing access/refresh tokens.
No Firebase project or client secret is required for this ID-token login flow.

Existing email/password users retain access. Matching an email address is *not*
sufficient to take over an existing account; sign in with the password first,
then use **Me → Link Google account**. Google-only users can reauthenticate using
Google for self-service account deletion. No password is invented or exposed.

## 1. Set up your own Google Cloud project (owner must do this)

1. Visit https://console.cloud.google.com/ and create/select a project named
   **FamilyMed** under your own Google account (not your cousin's).
2. Visit https://console.cloud.google.com/auth/overview and complete Google
   Auth Platform **Branding** and **Audience** for an external app. During testing,
   add only your own test Gmail accounts if the consent configuration requests them.
   For public release, configure the actual privacy-policy URL, support contact
   and any applicable production publishing/verification requirements.
3. Visit https://console.cloud.google.com/auth/clients and create a **Web application**
   OAuth client named `FamilyMed Backend Audience`. Save the client ID
   (the value ends in `.apps.googleusercontent.com`). The client ID is public.
   **Do not share/store any Google client secret in Flutter or GitHub.**
4. Create a separate **Android** OAuth client named `FamilyMed Android Debug`:
   - Android package: `com.familymed.familymed`
   - SHA-1: the certificate that signed the actual *debug APK* on your Ubuntu PC.
     Obtain it on the machine that built the APK:

     ```bash
     keytool -list -v -keystore ~/.android/debug.keystore \
       -alias androiddebugkey -storepass android -keypass android | grep 'SHA1:'
     ```

   - Repeat with an Android OAuth client for the **release upload key** when
     testing a directly distributed release APK signed by that key.
   - After Google Play accepts your app, also register its **Play App Signing**
     certificate fingerprint(s). Play-delivered APKs are signed by Google, not
     by the local upload key. See Play Console → App signing.
5. Do not configure Google People API unless the app actually needs that API.
   The initial sign-in only needs the standard Google account identity.

References:
- https://pub.dev/packages/google_sign_in_android
- https://developers.google.com/identity/gsi/web/guides/verify-google-id-token
- https://support.google.com/cloud/answer/15549257
- https://support.google.com/googleplay/android-developer/answer/9842756

## 2. Configure the backend and Flutter client

Set **exactly the same Web OAuth client ID** on both sides.

- FastAPI environment (Render dashboard, never commit private database credentials):
  `FAMILYMED_GOOGLE_WEB_CLIENT_ID=<YOUR_WEB_CLIENT_ID>`
- Flutter debug build on Ubuntu:

  ```bash
  cd mobile
  flutter pub get
  flutter gen-l10n
  dart run build_runner build
  flutter build apk --debug \
    --dart-define="FAMILYMED_GOOGLE_WEB_CLIENT_ID=<YOUR_WEB_CLIENT_ID>" \
    --dart-define="FAMILYMED_API_BASE_URL=<YOUR_REACHABLE_API_URL>/api/v1"
  ```

Android OAuth uses the registered package/SHA-1. Do not substitute the Android
client ID for the Web client ID in `serverClientId`.

## 3. Fix outdated lockfiles BEFORE merging this branch or deploying

The `main` backend lockfile is already stale. It misses password hashing and
JWT packages declared in `backend/pyproject.toml`, and now Google Auth must also
be included. The production Dockerfile uses `uv sync --frozen`, which will not
repair an outdated lock automatically.

Run on your trusted Ubuntu machine with internet access:

```bash
git fetch origin
git switch feat/google-sign-in-v1
cd backend && uv lock && uv sync --all-groups && uv run ruff check . && uv run pytest && cd ..
cd mobile && flutter pub get && flutter gen-l10n && dart run build_runner build && flutter analyze && flutter test && cd ..
git add backend/uv.lock mobile/pubspec.lock
git commit -m "build: refresh auth dependencies for Google login"
git push origin feat/google-sign-in-v1
```

Review dependency changes before committing. Do **not** force reset, clean,
overwrite, or discard other edits in a dirty checkout. Do not add credentials.
The CI Docker runtime-import gate must pass after this.

## 4. Real-device acceptance checklist

- New Google identity creates **one** FamilyMed account and family.
- Repeated Google sign-ins return that same account.
- Email/password users continue working without changes.
- Existing password user with same Google email is not automatically merged.
- Existing password user can link Google in **Me** and then sign in either way.
- Google sign-out clears FamilyMed session; the previous user's records never show.
- Wrong/expired token, unauthorized audience, and unverified Google email fail.
- Google-only account can delete via fresh Google reauthentication; password
  deletion still works for password accounts.
- Invalid/incorrect Android SHA-1 or client ID is diagnosed without using a
  production credential in code. Test in English/Bangla, on your actual phone.
- Build release AAB/Play internal test from the public HTTPS API URL.

## 5. Hosting after auth passes

1. Review and land `feat/free-beta-render-neon` PR #15 after green CI.
2. Create **Neon Free** PostgreSQL using the owner's connected account.
3. Use **Render Free** web service `familymed-beta-api`, confirm plan is **Free**,
   and privately configure `FAMILYMED_DATABASE_URL`, `FAMILYMED_SUPPORT_EMAIL`,
   `FAMILYMED_GOOGLE_WEB_CLIENT_ID`, and generated JWT secret.
4. Verify public `/api/v1/ready`, `/privacy`, and `/account-deletion`.
5. Use a signed Android test build pointed to Render via HTTPS; test Google
   sign-in, logout, deletion, and full manual medication workflow using only
   fictional/synthetic data.

**NOT production-safe:** Render Free sleeps after inactivity, has quotas, and
cannot guarantee real-time availability. Do not encourage reliance on free
beta for real medication reminders. Real data requires verified availability,
backup/restore, privacy practices and security hardening.

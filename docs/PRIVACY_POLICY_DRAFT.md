# FamilyMed Privacy Policy — DRAFT (not yet approved or published)

**Release blocker:** Replace the contact details and confirm the actual hosting, backup, deletion and retention practices with the app owner BEFORE displaying this as a final privacy policy or entering a Play Store URL.

Last drafted: 2026-10-10

FamilyMed is a medication-care organization and reminder app. It is not a medical diagnostic service, and reminder records are not a substitute for advice from a qualified healthcare professional.

## Information you provide
- Account name, email, and a securely hashed account password; account preferences such as language and timezone.
- Family-member names, relationships, optional date of birth, and care timezone.
- Medicines, strengths/forms, schedules, dose status and the date/time of recording actions.
- Notification choices and app data necessary to display reminders and sync records.

## Why we use information
We process this information to authenticate accounts, organize medication-care records, display dose history, and schedule relevant reminders. We do not need prescription images for the current manually-entered V1 workflow. We do not claim to diagnose illness or independently prescribe medication.

## Where the information is processed
FamilyMed's Android app stores account-scoped local caches, while its FastAPI server stores account and family-care data in PostgreSQL. The production server provider and region must be stated here once confirmed. A hosting vendor processes data to provide the service. Verify the actual subprocessors before publication.

## Data access and disclosures
FamilyMed should only make family-care records available to authenticated authorized users. It does not intentionally sell medication records or use them for targeted advertising. Disclosures may be necessary to service providers operating FamilyMed or to comply with lawful requirements; the owner must verify all third-party services and any monitoring/logging before publishing.

## Security
Android-to-production-API communication must use HTTPS. Password hashes and access-control checks are implemented in the backend. No internet-connected service can be guaranteed perfectly secure. We do not claim independent security certification.

## Notifications
The Android app may ask permission to deliver medication notifications and schedule alarms. These permissions support medication reminders, and users may change permissions through Android settings.

## Retention and account deletion
**MUST CONFIRM BEFORE PUBLICATION:** State how long account and family-care records, server backups, operational logs, and local mobile caches remain. Provide both an accessible in-app account-deletion path and a publicly available web resource for users who have uninstalled the app. Respond to authenticated deletion requests and ensure associated data is deleted or disclose legally necessary retention.

## Children's data
**MUST CONFIRM BEFORE PUBLICATION:** State the intended age group and whether caregivers may enter dependent minors' care records, with appropriate safeguards. Do not designate the app for children without the corresponding compliance work.

## Changes and contact
The owner will update this policy if FamilyMed's functionality or processing practices materially change. Support/privacy inquiries: **[APP OWNER MUST CONFIRM PUBLIC SUPPORT EMAIL]**.

**Do not deploy this draft as a completed policy.**

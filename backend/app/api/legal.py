"""Public privacy and account-deletion information for the Android listing."""

from html import escape
from urllib.parse import quote

from fastapi import APIRouter
from fastapi.responses import HTMLResponse

from app.config import get_settings

router = APIRouter(tags=["legal"])


def _page(title: str, body: str) -> HTMLResponse:
    return HTMLResponse(
        "<!doctype html><html lang='en'><head>"
        "<meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>"
        f"<title>{escape(title)} — FamilyMed</title>"
        "<style>body{font:16px/1.6 system-ui,sans-serif;max-width:760px;"
        "margin:32px auto;padding:0 20px;color:#202b2a}"
        "h1,h2{line-height:1.2}a{color:#155a50}</style>"
        "</head><body><nav><a href='/privacy'>Privacy</a> · "
        "<a href='/account-deletion'>Account deletion</a></nav>"
        f"<main>{body}</main></body></html>",
        headers={"Cache-Control": "public, max-age=3600"},
    )


@router.get("/privacy", response_class=HTMLResponse, include_in_schema=False)
async def privacy() -> HTMLResponse:
    email = escape(str(get_settings().support_email or "support email not yet configured"))
    body = (
        "<h1>FamilyMed Privacy Policy</h1>"
        "<p>Effective: October 2026</p>"
        "<p>FamilyMed helps caregivers organize family medication records, routines, "
        "and reminders. It does not provide a diagnosis or prescription.</p>"
        "<h2>Information handled</h2>"
        "<p>Account names, email addresses, password hashes, preferred languages and "
        "timezones; family-member names, relationships, optional dates of birth; "
        "medicine names, strengths, routines, reminders and dose history. "
        "The app keeps account-scoped local copies to support normal operation.</p>"
        "<h2>Purposes</h2>"
        "<p>We use this information to register accounts, authenticate users, "
        "save medication-care data, and display reminders and history. "
        "The current V1 manual-care workflow does not require prescription images.</p>"
        "<h2>Hosting and sharing</h2>"
        "<p>Account and care records are processed on FamilyMed's API and PostgreSQL "
        "database, with infrastructure supplied by the hosting provider. "
        "We do not sell medication-care records or use them for targeted advertising. "
        "Information may be processed by infrastructure providers needed to run "
        "the service, or disclosed where legally required.</p>"
        "<h2>Security</h2>"
        "<p>Production mobile-to-server traffic uses HTTPS, passwords are hashed, "
        "and access to care records requires account authentication. "
        "No internet service can guarantee absolute security.</p>"
        "<h2>Notifications</h2>"
        "<p>Android notification and alarm permissions support scheduled reminders. "
        "You can change notification permissions in your device settings.</p>"
        "<h2>Retention and deletion</h2>"
        "<p>Care records remain in the live database while the account is active. "
        "Authenticated account deletion removes the account and associated "
        "single-owner family-care records from the live database; "
        "operational logs and database backups may persist for their respective "
        "retention periods. Shared-family cases require support-assisted deletion. "
        "See <a href='/account-deletion'>account deletion instructions</a> "
        "for a request pathway even without the app.</p>"
        "<h2>Children</h2>"
        "<p>FamilyMed is intended for caregivers, not use by children. "
        "A caregiver may optionally organize care records for dependents.</p>"
        "<h2>Contact</h2>"
        f"<p>Privacy and data requests: <a href='mailto:{email}'>{email}</a>.</p>"
    )
    return _page("Privacy Policy", body)


@router.get("/account-deletion", response_class=HTMLResponse, include_in_schema=False)
async def account_deletion() -> HTMLResponse:
    support = str(get_settings().support_email or "support email not yet configured")
    email = escape(support)
    mailto = escape(
        f"mailto:{support}?subject={quote('FamilyMed account deletion request')}",
        quote=True,
    )
    return _page(
        "Account deletion",
        "<h1>Request deletion of your FamilyMed account</h1>"
        "<p>If FamilyMed is installed and you can sign in: open "
        "<strong>Me → Delete account</strong>, enter your password, "
        "and confirm permanent deletion. This also removes the "
        "single-owner family medication-care records from the live database.</p>"
        "<p>If you cannot access the app or already uninstalled it, "
        "you can request deletion without reinstalling: "
        f"<a href='{mailto}'>email {email}</a> from the account's email address. "
        "Mention your FamilyMed account email so support can verify account ownership. "
        "<strong>Never send your password, medication details, or health records by email.</strong>"
        "</p><p>Shared-family data and backup/log retention may require "
        "individual review. Support will explain any necessary retention before "
        "processing the request.</p>",
    )

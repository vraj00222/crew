# /// script
# dependencies = [
#   "google-api-python-client",
#   "google-auth-oauthlib",
#   "google-auth",
# ]
# ///

from __future__ import annotations

import argparse
import base64
import json
import sys
from collections import Counter
from datetime import datetime, time, timedelta, timezone
from email.message import EmailMessage
from email.policy import SMTP
from email.utils import format_datetime, formataddr, make_msgid
from pathlib import Path
from typing import Any


SCOPES = [
    "https://www.googleapis.com/auth/gmail.modify",
    "https://www.googleapis.com/auth/calendar",
]

SEED_LABEL_NAME = "crew-demo-seed"
CALENDAR_MARKER_KEY = "crewDemoSeed"
CALENDAR_MARKER_VALUE = "1"
DRY_RUN_TO = "authenticated-user@example.com"


def configure_stdout() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if hasattr(sys.stderr, "reconfigure"):
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")


def script_dir() -> Path:
    return Path(__file__).resolve().parent


def path_from_script(value: str) -> Path:
    path = Path(value)
    if path.is_absolute():
        return path
    return script_dir() / path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Seed a throwaway Google account with demo Gmail and Calendar data."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Build and validate everything without credentials or network.",
    )
    parser.add_argument(
        "--wipe",
        action="store_true",
        help="Delete previously seeded Gmail messages and Calendar events, then exit.",
    )
    target = parser.add_mutually_exclusive_group()
    target.add_argument(
        "--emails-only",
        action="store_true",
        help="Only wipe/seed Gmail.",
    )
    target.add_argument(
        "--calendar-only",
        action="store_true",
        help="Only wipe/seed Calendar.",
    )
    parser.add_argument(
        "--yes",
        "-y",
        action="store_true",
        help="Skip the 'is this the right account?' confirmation. For reseeding fast.",
    )
    parser.add_argument(
        "--credentials",
        default="credentials.json",
        help="OAuth client JSON path, relative to this script by default.",
    )
    parser.add_argument(
        "--token",
        default="token.json",
        help="OAuth token JSON path, relative to this script by default.",
    )
    return parser.parse_args()


def clean_public_fields(item: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in item.items() if not key.startswith("_")}


def load_fixtures() -> tuple[list[dict[str, Any]], list[dict[str, Any]], dict[str, Any]]:
    fixture_path = script_dir() / "fixtures.json"
    with fixture_path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)

    emails = [clean_public_fields(item) for item in data.get("emails", [])]
    calendar = [clean_public_fields(item) for item in data.get("calendar", [])]
    meta = clean_public_fields(data.get("meta", {}))
    return emails, calendar, meta


def local_datetime_for(day_offset: int, clock_text: str, now_local: datetime) -> datetime:
    hour_text, minute_text = clock_text.split(":", 1)
    clock = time(hour=int(hour_text), minute=int(minute_text))
    target_date = now_local.date() + timedelta(days=int(day_offset))

    # A naive datetime converted with astimezone() is interpreted in the
    # machine's local timezone, including that date's DST rules.
    return datetime.combine(target_date, clock).astimezone()


def resolve_email_times(
    emails: list[dict[str, Any]], now_utc: datetime
) -> list[dict[str, Any]]:
    resolved: list[dict[str, Any]] = []
    for item in emails:
        sent_at = now_utc - timedelta(hours=int(item["hours_ago"]))
        resolved.append({**item, "sent_at": sent_at})
    return resolved


def resolve_calendar_times(
    events: list[dict[str, Any]], now_local: datetime
) -> list[dict[str, Any]]:
    resolved: list[dict[str, Any]] = []
    for item in events:
        start_at = local_datetime_for(int(item["days_ahead"]), item["start"], now_local)
        end_at = local_datetime_for(int(item["days_ahead"]), item["end"], now_local)
        resolved.append({**item, "start_at": start_at, "end_at": end_at})
    return resolved


def build_mime_message(item: dict[str, Any], to_email: str) -> EmailMessage:
    msg = EmailMessage()
    msg["From"] = formataddr((str(item["from_name"]), str(item["from_email"])))
    msg["To"] = to_email
    msg["Subject"] = str(item["subject"])
    msg["Date"] = format_datetime(item["sent_at"])
    msg["Message-ID"] = make_msgid(idstring=str(item["id"]), domain="crew-demo-seed.local")
    msg["X-Crew-Demo-Seed"] = "1"
    msg.set_content(str(item["body"]), charset="utf-8")
    return msg


def raw_message_for(item: dict[str, Any], to_email: str) -> str:
    msg = build_mime_message(item, to_email)
    return base64.urlsafe_b64encode(msg.as_bytes(policy=SMTP)).decode("ascii")


def gmail_label_ids_for(item: dict[str, Any], seed_label_id: str) -> list[str]:
    label_ids = ["INBOX", "UNREAD", seed_label_id]
    if item.get("important") is True:
        label_ids.append("IMPORTANT")
    if item.get("starred") is True:
        label_ids.append("STARRED")
    return label_ids


def calendar_body_for(item: dict[str, Any]) -> dict[str, Any]:
    return {
        "summary": str(item["summary"]),
        "start": {"dateTime": item["start_at"].isoformat()},
        "end": {"dateTime": item["end_at"].isoformat()},
        "extendedProperties": {
            "private": {CALENDAR_MARKER_KEY: CALENDAR_MARKER_VALUE}
        },
    }


def trim(value: Any, width: int) -> str:
    text = str(value).replace("\n", " ")
    if len(text) <= width:
        return text
    return text[: max(0, width - 3)] + "..."


def print_dry_run_tables(
    emails: list[dict[str, Any]],
    events: list[dict[str, Any]],
    email_raws: list[str],
    event_bodies: list[dict[str, Any]],
    wipe_first: bool,
) -> None:
    if wipe_first:
        print("Dry run: would wipe existing crew-demo-seed Gmail and Calendar items first.")
    print()
    print("Emails that would be inserted")
    print(f"{'#':>2}  {'Date':<22}  {'Category':<15}  {'From':<20}  Subject")
    print("-" * 92)
    for idx, item in enumerate(emails, start=1):
        sent = item["sent_at"].astimezone().strftime("%Y-%m-%d %H:%M %Z")
        print(
            f"{idx:>2}  {sent:<22}  {trim(item['category'], 15):<15}  "
            f"{trim(item['from_name'], 20):<20}  {trim(item['subject'], 42)}"
        )

    print()
    print("Calendar events that would be inserted")
    print(f"{'#':>2}  {'Start':<22}  {'End':<22}  Summary")
    print("-" * 78)
    for idx, item in enumerate(events, start=1):
        start = item["start_at"].strftime("%Y-%m-%d %H:%M %Z")
        end = item["end_at"].strftime("%Y-%m-%d %H:%M %Z")
        print(
            f"{idx:>2}  {start:<22}  {end:<22}  {trim(item['summary'], 28)}"
        )

    print()
    print(
        f"Built {len(email_raws)} RFC822/base64url messages and "
        f"{len(event_bodies)} Calendar request bodies."
    )


def validate_meta(emails: list[dict[str, Any]], meta: dict[str, Any]) -> list[str]:
    counts = Counter(str(item["category"]) for item in emails)
    failures: list[str] = []

    expected_total = int(meta["total"])
    if len(emails) != expected_total:
        failures.append(f"meta.total={expected_total}, actual emails={len(emails)}")

    archive_total = counts["newsletter"] + counts["noise"] + counts["travel"]
    expected_archive = int(meta["archive_expected"])
    if archive_total != expected_archive:
        failures.append(
            "newsletter+noise+travel="
            f"{archive_total}, meta.archive_expected={expected_archive}"
        )

    expected_remaining = int(meta["remaining_expected"])
    if counts["needs-reply"] != expected_remaining:
        failures.append(
            f"needs-reply={counts['needs-reply']}, "
            f"meta.remaining_expected={expected_remaining}"
        )

    return failures


def run_dry_run(
    emails: list[dict[str, Any]],
    events: list[dict[str, Any]],
    meta: dict[str, Any],
    wipe_first: bool,
) -> int:
    email_raws = [raw_message_for(item, DRY_RUN_TO) for item in emails]
    event_bodies = [calendar_body_for(item) for item in events]

    print_dry_run_tables(emails, events, email_raws, event_bodies, wipe_first)

    counts = Counter(str(item["category"]) for item in emails)
    count_text = ", ".join(f"{name}={counts[name]}" for name in sorted(counts))
    print(f"Category counts: {count_text}")

    failures = validate_meta(emails, meta)
    if failures:
        print()
        print("ASSERTION FAILED")
        for idx, failure in enumerate(failures, start=1):
            print(f"{idx}. {failure}")
        return 1

    print(
        f"Dry run OK: {len(emails)} emails and {len(events)} calendar events "
        "would be created."
    )
    return 0


def print_missing_credentials_help(credentials_path: Path) -> None:
    print(f"Missing OAuth credentials file: {credentials_path}")
    print()
    print("Create one like this:")
    print("1. Open Google Cloud Console and create a new project.")
    print("2. Enable Gmail API and Google Calendar API.")
    print("3. Configure OAuth consent screen: External, then add yourself as a test user.")
    print("4. Go to Credentials -> OAuth client ID -> Desktop app.")
    print("5. Download the JSON and save it as credentials.json next to seed.py.")


def authenticate(credentials_path: Path, token_path: Path):
    from google.auth.transport.requests import Request
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow

    creds = None
    if token_path.exists():
        creds = Credentials.from_authorized_user_file(str(token_path), SCOPES)

    if creds and creds.expired and creds.refresh_token:
        try:
            creds.refresh(Request())
        except Exception:
            creds = None

    if not creds or not creds.valid:
        flow = InstalledAppFlow.from_client_secrets_file(str(credentials_path), SCOPES)
        creds = flow.run_local_server(port=0)

    token_path.write_text(creds.to_json(), encoding="utf-8")
    return creds


def confirm_account(gmail, assume_yes: bool) -> bool:
    """Show which mailbox we are about to write to, and get a yes.

    This script inserts 18 fake emails and permanently batchDeletes anything
    carrying the seed label. Both are scoped to our own marker, so the blast
    radius is small -- but the account is whatever token.json happens to hold,
    and 'I OAuthed with my real Gmail by accident' is a one-keystroke mistake.
    Print the address and make someone look at it.
    """
    profile = gmail.users().getProfile(userId="me").execute()
    address = str(profile["emailAddress"])
    total = int(profile.get("messagesTotal", 0))

    print(f"\nTarget account: {address}  ({total} messages in mailbox)")
    if assume_yes:
        print("--yes given, proceeding.\n")
        return True

    # A throwaway demo account has a nearly empty mailbox. A real one does not.
    if total > 500:
        print("!! This mailbox has a lot of mail in it. That is not what a fresh")
        print("!! demo account looks like. Check the address above very carefully.")

    try:
        answer = input("Seed this account? [y/N] ").strip().lower()
    except EOFError:
        print("Not a terminal and no --yes given; refusing to touch the account.")
        return False

    if answer not in {"y", "yes"}:
        print("Aborted, nothing changed.")
        return False
    print()
    return True


def build_google_services(credentials_path: Path, token_path: Path):
    from googleapiclient.discovery import build

    creds = authenticate(credentials_path, token_path)
    gmail = build("gmail", "v1", credentials=creds)
    calendar = build("calendar", "v3", credentials=creds)
    return gmail, calendar


def get_or_create_seed_label(gmail) -> str:
    labels_response = gmail.users().labels().list(userId="me").execute()
    for label in labels_response.get("labels", []):
        if label.get("name") == SEED_LABEL_NAME:
            return str(label["id"])

    # This label is the Gmail-side idempotency marker. Every seeded message gets
    # it, so a later wipe can find exactly the fake demo inbox and nothing else.
    created = (
        gmail.users()
        .labels()
        .create(
            userId="me",
            body={
                "name": SEED_LABEL_NAME,
                "labelListVisibility": "labelShow",
                "messageListVisibility": "show",
            },
        )
        .execute()
    )
    return str(created["id"])


def list_seeded_message_ids(gmail) -> list[str]:
    ids: list[str] = []
    request = (
        gmail.users()
        .messages()
        .list(userId="me", q=f"label:{SEED_LABEL_NAME}", maxResults=500)
    )
    while request is not None:
        response = request.execute()
        ids.extend(str(item["id"]) for item in response.get("messages", []))
        request = gmail.users().messages().list_next(request, response)
    return ids


def wipe_gmail(gmail) -> int:
    ids = list_seeded_message_ids(gmail)
    if not ids:
        print("Gmail wipe: no crew-demo-seed messages found.")
        return 0

    for offset in range(0, len(ids), 1000):
        batch = ids[offset : offset + 1000]
        gmail.users().messages().batchDelete(
            userId="me", body={"ids": batch}
        ).execute()
    print(f"Gmail wipe: deleted {len(ids)} crew-demo-seed messages.")
    return len(ids)


def list_seeded_calendar_events(calendar) -> list[dict[str, Any]]:
    now = datetime.now(timezone.utc)
    time_min = (now - timedelta(days=3650)).isoformat()
    time_max = (now + timedelta(days=3650)).isoformat()
    events: list[dict[str, Any]] = []

    request = (
        calendar.events()
        .list(
            calendarId="primary",
            privateExtendedProperty=f"{CALENDAR_MARKER_KEY}={CALENDAR_MARKER_VALUE}",
            timeMin=time_min,
            timeMax=time_max,
            singleEvents=True,
            showDeleted=False,
            maxResults=2500,
        )
    )
    while request is not None:
        response = request.execute()
        events.extend(response.get("items", []))
        request = calendar.events().list_next(request, response)
    return events


def wipe_calendar(calendar) -> int:
    events = list_seeded_calendar_events(calendar)
    if not events:
        print("Calendar wipe: no crew-demo-seed events found.")
        return 0

    total = len(events)
    for idx, event in enumerate(events, start=1):
        summary = event.get("summary", "(untitled)")
        print(f"[{idx:>2}/{total}] deleting  {trim(summary, 52)}")
        calendar.events().delete(calendarId="primary", eventId=event["id"]).execute()
    print(f"Calendar wipe: deleted {total} crew-demo-seed events.")
    return total


def seed_gmail(gmail, emails: list[dict[str, Any]]) -> int:
    profile = gmail.users().getProfile(userId="me").execute()
    to_email = str(profile["emailAddress"])
    seed_label_id = get_or_create_seed_label(gmail)

    # insert, not send: fixture senders are fake .example.com identities. We are
    # placing realistic-looking messages directly into the demo mailbox.
    total = len(emails)
    for idx, item in enumerate(emails, start=1):
        raw = raw_message_for(item, to_email)
        gmail.users().messages().insert(
            userId="me",
            body={
                "raw": raw,
                "labelIds": gmail_label_ids_for(item, seed_label_id),
            },
            internalDateSource="dateHeader",
        ).execute()
        print(
            f"[{idx:>2}/{total}] inserted  {trim(item['from_name'], 20)} "
            f"\u2014 {trim(item['subject'], 58)}"
        )
    return total


def seed_calendar(calendar, events: list[dict[str, Any]]) -> int:
    total = len(events)
    for idx, item in enumerate(events, start=1):
        body = calendar_body_for(item)
        calendar.events().insert(calendarId="primary", body=body).execute()
        start_text = item["start_at"].strftime("%a %H:%M")
        print(
            f"[{idx:>2}/{total}] created   {start_text}  "
            f"{trim(item['summary'], 58)}"
        )
    return total


def main() -> int:
    configure_stdout()
    args = parse_args()

    credentials_path = path_from_script(args.credentials)
    token_path = path_from_script(args.token)

    raw_emails, raw_events, meta = load_fixtures()
    now_utc = datetime.now(timezone.utc)
    now_local = datetime.now().astimezone()
    emails = resolve_email_times(raw_emails, now_utc)
    events = resolve_calendar_times(raw_events, now_local)

    if args.dry_run:
        return run_dry_run(emails, events, meta, wipe_first=True)

    if not credentials_path.exists():
        print_missing_credentials_help(credentials_path)
        return 1

    do_gmail = not args.calendar_only
    do_calendar = not args.emails_only

    gmail, calendar = build_google_services(credentials_path, token_path)

    if not confirm_account(gmail, args.yes):
        return 1

    wiped_gmail = 0
    wiped_calendar = 0
    if do_gmail:
        wiped_gmail = wipe_gmail(gmail)
    if do_calendar:
        wiped_calendar = wipe_calendar(calendar)

    if args.wipe:
        print(
            f"Done: wiped {wiped_gmail} Gmail messages and "
            f"{wiped_calendar} Calendar events."
        )
        return 0

    inserted = 0
    created = 0
    if do_gmail:
        inserted = seed_gmail(gmail, emails)
    if do_calendar:
        created = seed_calendar(calendar, events)

    print(
        f"Done: wiped {wiped_gmail} Gmail messages, wiped {wiped_calendar} "
        f"Calendar events, inserted {inserted} emails, created {created} events."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

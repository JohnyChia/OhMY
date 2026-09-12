"""Prototype-only, rate-limited account lookup. Never returns user records."""
import os
import re
import time
from collections import deque
from functools import lru_cache
from pathlib import Path
from threading import Lock

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel, StrictStr
from supabase import ClientOptions, create_client

load_dotenv(os.getenv("AUTH_ENV_FILE", str(Path(__file__).parent / ".env")))
app = FastAPI(title="OhMY Authentication Support")

EMAIL_PATTERN = re.compile(
    r"[A-Za-z0-9]+(?:[._-][A-Za-z0-9]+)*@"
    r"[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?"
    r"(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)*"
    r"\.[A-Za-z]{2,63}"
)


class EmailLookup(BaseModel):
    email: StrictStr


class LookupLimiter:
    """In-memory limits for this single-process laptop prototype."""
    def __init__(self):
        self.lock = Lock()
        self.global_requests = deque()
        self.clients = {}

    def allow(self, ip):
        now = time.monotonic()
        with self.lock:
            while self.global_requests and self.global_requests[0] <= now - 60:
                self.global_requests.popleft()
            for key in list(self.clients):
                if not self.clients[key] or self.clients[key][-1] <= now - 60:
                    del self.clients[key]
            requests = self.clients.setdefault(ip, deque())
            while requests and requests[0] <= now - 60:
                requests.popleft()
            if len(requests) >= 5 or len(self.global_requests) >= 100:
                return False
            requests.append(now)
            self.global_requests.append(now)
            return True


limiter = LookupLimiter()


@lru_cache(maxsize=1)
def admin_client():
    url = os.getenv("SUPABASE_URL", "")
    key = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")
    if not url or not key:
        raise RuntimeError("Missing server-side Supabase configuration")
    return create_client(
        url, key,
        options=ClientOptions(auto_refresh_token=False, persist_session=False),
    )


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/auth/email-registered")
def email_registered(body: EmailLookup, request: Request):
    if not limiter.allow(request.client.host if request.client else "unknown"):
        raise HTTPException(429, "Too many attempts. Please wait a minute.",
                            headers={"Retry-After": "60"})
    email = body.email.strip().lower()
    parts = email.split("@")
    if (len(email) > 254 or not EMAIL_PATTERN.fullmatch(email)
            or len(parts[0]) > 64
            or any(len(label) > 63 for label in parts[-1].split("."))):
        raise HTTPException(400, "Please enter a valid email address.")
    try:
        # No new public profile/email table and no auth.users SELECT grants.
        # Pagination is suitable for a small university prototype; move to
        # an indexed, server-only lookup before scaling to large user counts.
        for page in range(1, 101):
            users = admin_client().auth.admin.list_users(page=page, per_page=200)
            if any((user.email or "").lower() == email for user in users):
                return {"registered": True}
            if len(users) < 200:
                return {"registered": False}
        raise RuntimeError("Account lookup exceeded prototype capacity")
    except Exception:
        # Never turn an unavailable database into 'not registered'.
        # Do not log emails, admin credentials or full user records.
        raise HTTPException(503, "Cannot check your account right now. Try again.") from None

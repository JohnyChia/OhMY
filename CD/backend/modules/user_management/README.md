# Authentication support (laptop prototype)

Forgot password checks Supabase Auth before Flutter sends the recovery email.
An unknown account stays on the email page with "This email address is not
registered." Database errors never count as an unknown account.

This is an intentionally account-enumerating prototype requirement. The
endpoint returns only a boolean, never user records, UUIDs, passwords or keys.
It limits each IP to 5 requests/minute and the process to 100 requests/minute.
Use ONE process/worker. Limits reset after restart. For public deployment,
add persistent distributed rate limits and CAPTCHA, or use Supabase's standard
non-enumerating recovery response instead. CORS is not an access control.

## Start

Uses FastAPI, uvicorn, python-dotenv and supabase, already installed in the
Verified Traveller Python environment. No OCR or face models are loaded here.

1. Copy `.env.example` to `.env` and fill in backend credentials, or set
   `AUTH_ENV_FILE` to an existing backend `.env` for the SAME Supabase project.
   Never put that file or its service-role key in Flutter or GitHub.
2. From this folder, run (adjust the Python path for your existing environment):

```powershell
..\verified_traveller\.venv\Scripts\python.exe -m uvicorn app:app --host 0.0.0.0 --port 8001
```

Health: `http://127.0.0.1:8001/health`.
Flutter defaults to `http://10.0.2.2:8001` (standard Android emulator).
For a real phone, set `--dart-define=AUTH_API_URL=http://YOUR_LAPTOP_IP:8001`.
Leave this service running when testing forgot password. Ports 3000, 3001
and 8000 and teammates' services are unchanged.

No SQL, public email table, RLS changes or auth.users SELECT grants are needed.
The lookup uses paginated Admin API calls, suitable for this small prototype.
It compares the trimmed/lowercased actual Auth email, not Gmail aliases.
At large scale use an indexed server-only lookup; the capacity guard returns
unavailable rather than falsely reporting an unregistered account.

Tests: run the same Python executable with `-m unittest test_app.py` here.

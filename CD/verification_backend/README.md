# Verified Traveller local prototype backend

This service is for the university demonstration. It is not legal eKYC and
must only be tested with synthetic identity documents.

## One-time setup

1. Run the Supabase migration in `supabase/migrations/20260901_identity_verifications.sql`.
2. Install Tesseract OCR (free) and note the path to `tesseract.exe`.
3. In this folder create a Python 3.13 virtual environment and install
   `requirements.txt` (use `py -3.13 -m venv .venv`).
4. Copy `.env.example` to `.env`. Put the Supabase service-role key only in
   this local file. Never put it in Flutter or commit it.
5. Run `python setup_models.py` to download YuNet and SFace models.

## Run during the demo

```powershell
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Check `http://127.0.0.1:8000/health`. The Android Studio emulator uses
`http://10.0.2.2:8000`. A physical phone needs the laptop LAN address through
Flutter's `VERIFICATION_API_URL` dart define.

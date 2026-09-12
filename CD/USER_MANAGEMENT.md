# User Management and Verified Traveller module

This module contains the Flutter authentication, profile, travel-preference,
and Verified Traveller prototype flows. It is kept under
`flutter_app/lib/user_management` so it can be reviewed and integrated without
overwriting the map, routing, weather, or community modules.

## Run the Flutter module

From `CD/flutter_app`, run:

```powershell
flutter pub get
flutter run -t lib/user_management_main.dart `
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=YOUR_CLIENT_SAFE_PUBLISHABLE_KEY
```

The Supabase secret/service-role key must never be passed to Flutter.

## Verified Traveller backend

The university-prototype backend is in
`CD/backend/modules/verified_traveller`. It performs
synthetic document OCR, head-turn checks, and document/selfie face comparison.
It is not legal eKYC and must only be tested with synthetic documents.

1. Copy `backend/modules/verified_traveller/.env.example` to
   `backend/modules/verified_traveller/.env`.
2. Add the client-safe key and the backend-only Supabase secret key locally.
3. Install the pinned Python dependencies and download the free vision models
   as described in `backend/modules/verified_traveller/README.md`.
4. Start the backend on port 8000 before testing verification.

The Android emulator connects to the laptop backend through
`http://10.0.2.2:8000`. Override `VERIFICATION_API_URL` with a Dart define when
testing on a physical phone.

## Database

The SQL migrations are in `CD/supabase/migrations`. They configure traveller
preferences and the RLS-protected identity verification records. Coordinate
before running a migration against a shared Supabase project.

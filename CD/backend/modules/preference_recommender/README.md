# Preference Recommender backend module

This module owns Google Places discovery, review tagging, candidate planning,
similarity ranking, the development attraction dataset, and its regression
checks.

The shared Express gateway remains at `backend/server.js` and exposes this
module's API endpoints. Run commands from `backend`:

```powershell
npm run tagging
npm run test:tagging
npm run test:recommendation
```

`collectPlaces.js` is the development data-collection utility. It reads the
shared configuration from `backend/.env` when launched from the backend
directory.

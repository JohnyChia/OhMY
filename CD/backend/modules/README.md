# Backend modules

The main Preference Recommender Express service remains in the parent
`backend` directory. Additional team services are isolated here so they keep
their own runtimes, dependencies, environment variables, and ports.

## Shared gateway

`backend/server.js` is the API gateway and static prototype host. Feature
implementations are grouped below by module:

- `preference_recommender` — Places discovery, tagging, candidate planning,
  ranking, data collection, and regression tests.
- `weather_traffic` — Weather lookup and traffic-aware route processing.
- `ai_chatbot` — Standalone Node.js conversational assistant on port 3001.
- `verified_traveller` — Standalone Python verification prototype on port 8000.

## AI Chatbot

Location: `backend/modules/ai_chatbot`

```powershell
cd backend/modules/ai_chatbot
Copy-Item .env.example .env
npm.cmd install
npm.cmd start
```

The local service uses port `3001`, while the main recommender service keeps
port `3000`.

## Verified Traveller

Location: `backend/modules/verified_traveller`

Follow its local `README.md` for the Python environment, OCR models, Supabase
configuration, and startup instructions. It uses port `8000` by default.

Secrets must remain in each module's ignored `.env` file. Never expose a
Supabase service-role key in Flutter.

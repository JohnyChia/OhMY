# Nova travel assistant

Nova is a conversational layer over OhMY's existing travel modules. It owns
language understanding and a small, validated action contract; it does not own
place discovery, recommendation ranking, navigation, weather data, or user
preferences.

## Request flow

1. A Supabase access token identifies the user.
2. Nova loads that user's `traveler_profiles` preferences and recent session
   messages.
3. A local guard handles obvious gibberish and abuse-only messages without an
   AI request.
4. Gemini classifies the user's English, Bahasa Malaysia, Mandarin, or mixed
   request and conservatively corrects obvious place-name shorthand.
5. An allowlisted tool retrieves factual data. Recommendation requests call
   the existing `preference_recommender` HTTP API on port 3000.
6. Gemini produces one short response grounded only in the tool result.
7. A typed action may hand a verified destination to the existing solo-trip
   owner. The Flutter client, not the model, performs navigation.

The normal path uses at most two Gemini calls. Classification receives only
the two most recent messages, and output budgets are configured in
`src/config/tokenConfig.js`.

## Configuration

Set these in `CD/backend/.env`; `run-ohmy.ps1` forwards them to Nova:

```dotenv
GEMINI_API_KEY=your_server_side_key
GEMINI_TEXT_MODEL=gemini-3.5-flash-lite
GEMINI_AUDIO_MODEL=gemini-3.5-flash-lite
PREFERENCE_RECOMMENDER_URL=http://127.0.0.1:3000
```

Groq remains an optional fallback. It is not required by the launcher when a
Gemini key is configured.

## Verification

From `CD/backend/modules/ai_chatbot`:

```powershell
npm.cmd test
```

From `CD/backend`:

```powershell
npm.cmd run test:recommendation
```

# Ordered module integration — 2026-09-12

Integrated on `but-it-works-on-my-pc-bro` in this order:

1. `origin/reco-and-navi-sdk` (`60ea24e`)
2. `origin/Community-Discovery`
3. `origin/ai-chatbot` (`1bcf43e`)

The AI branch contains an older full-project snapshot. Conflicts outside its AI module were resolved using the newer recommender/community/group/auth implementations. The current app shell hosts Nova's owner-action dispatcher and voice overlay; Android retains the cached splash engine alongside the incoming voice/attachment bridges. Nova opens the current destination search for place selection, rather than auto-starting an ambiguous search result, and cannot start solo travel while group membership is active.

Saved local group-travel and launcher fixes were reapplied. The recovery stash `OhMY local fixes before ordered module merges 20260912` and branch `backup/pre-module-merges-20260912` remain available. Local environment files were not changed.

## Verification

- Android debug APK built successfully.
- App `lib` and `test` analysis: no issues.
- Recommender Tagger V2 and area/destination search contracts: passed.
- Community backend build: passed; 26 tests passed.
- Community Flutter tests: 8 passed.
- AI backend: 52 of 55 tests passed. Three transcript-selection tests fail in `src/routes/voice.test.js`; the tested `voice.js` and tests match the incoming AI branch. Its quality scoring selects the longer English candidate in those multilingual fixtures. This behavior was not silently changed during integration.

## Deployment boundaries

No GitHub push or live Supabase migration application was performed. Incoming Tagger V2, saved-travel-item, and community ownership/history/spam/tag-mapping migrations must be reviewed against the deployed database before applying. Repository merge completion does not mean those new database-dependent features are deployed or live voice-provider calls have been tested.

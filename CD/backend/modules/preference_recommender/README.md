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
npm run test:tagger-v2
```

## Tagger V2

Tagger V2 adds language-aware review normalization, Unicode-safe tokenization,
weighted review evidence, conservative metadata fallback for places without
reviews, change fingerprints, and atomic Supabase tag replacement. Its ranking
uses preference coverage, evidence confidence, and cultural relevance only;
distance is not part of the score.

Fingerprints compare canonical, sorted assignments. Confidence is rounded to
two decimal places, so immaterial floating-point changes do not rewrite tag
relationships; added/removed tags, meaningful confidence changes, evidence,
or source changes do. An unchanged result only advances its version and audit
timestamps. A changed result, including an empty result, atomically replaces
all `place_tags` relationships.

Apply these migrations before expecting V2 results to persist:

```text
supabase/migrations/20260910_preference_recommender_cache.sql
supabase/migrations/20260912_preference_recommender_tagger_v2.sql
```

The discovery limits can be tuned with:

```dotenv
TAGGER_VERSION=rule-nlp-v2-2026-09-12
RECOMMENDATION_RESULTS_PER_TYPE=10
RECOMMENDATION_CANDIDATE_LIMIT=40
RECOMMENDATION_DETAILS_CONCURRENCY=4
RECOMMENDATION_MAXIMUM_SEARCH_TYPES=6
```

Retagging is incremental and resumable:

```powershell
node modules/preference_recommender/scripts/retag-cached-places.js --dry-run
node modules/preference_recommender/scripts/retag-cached-places.js --from-version rule-nlp-2026-09-10 --limit 100
node modules/preference_recommender/scripts/retag-cached-places.js --after-id 100 --limit 100
```

Raw Google review text is processed in memory and is not stored by this
module. Supabase retains only aggregate language and evidence information.

`collectPlaces.js` is the development data-collection utility. It reads the
shared configuration from `backend/.env` when launched from the backend
directory.

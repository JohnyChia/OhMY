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

## Tagger V4 cultural validation

Google cultural and historical place types are candidate-discovery metadata,
not a final cultural verdict. They may strengthen a cultural tag that already
has meaningful review evidence, but cannot create a cultural tag alone. One
review is sufficient only when it passes the existing NLP evidence score,
specificity, negation and 10% place-support rules. Residential/private-property
types and unprotected residential names remain excluded even when Google
supplies a cultural or historical category.

This policy is versioned as
`rule-nlp-v4-adaptive-cultural-evidence-2026-09-13`, causing older cache rows to
be re-evaluated. Places whose new result is empty have their stale relationships
removed by the atomic replacement RPC.

Apply these migrations before expecting V2 results to persist:

```text
supabase/migrations/20260910_preference_recommender_cache.sql
supabase/migrations/20260912_preference_recommender_tagger_v2.sql
```

The discovery limits can be tuned with:

```dotenv
TAGGER_VERSION=rule-nlp-v4-adaptive-cultural-evidence-2026-09-13
RECOMMENDATION_RESULTS_PER_TYPE=15
RECOMMENDATION_CANDIDATE_LIMIT=70
RECOMMENDATION_DISCOVERY_LIMIT=130
RECOMMENDATION_DETAILS_CONCURRENCY=4
RECOMMENDATION_MAXIMUM_SEARCH_TYPES=10
RECOMMENDATION_DISPLAY_LIMIT=30
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

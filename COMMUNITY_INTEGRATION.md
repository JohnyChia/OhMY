# Community Discovery handoff

The integrated source of truth is the root `community_discovery/` package. The OhMY app consumes it from `CD/flutter_app` using a local path dependency; do not restore the removed duplicate `CD/flutter_app/lib/community_discovery` folder.

For migration order, Node deployment, Flutter configuration, Profile bookmarks, Travel History Create/Edit, Start Journey callbacks, security, and verification, follow [`community_discovery/INTEGRATION.md`](community_discovery/INTEGRATION.md).

Important integration rules:

- Keep one `CommunityController` in the application shell.
- Only real solo Profile Travel History rows expose Create/Edit Post; group trips and itinerary stops are outside this integration.
- The history row's displayed destination is locked onto the post.
- Apply only Community migrations after the shared Travel History migration.
- Never commit `.env` files, service-role keys, Groq keys, or unrestricted Google server keys.
- Preserve [`community_discovery/CREATE_POST_TEST_CASES.md`](community_discovery/CREATE_POST_TEST_CASES.md) for manual QA.

# Track A validation: Research Terminal PostgreSQL search

## Root cause

The Hermes skill's search operation already posts to the canonical authenticated endpoint POST /api/v1/hermes/knowledge/search. In create_app(), that legacy ORM-backed Hermes router is registered in SQLite mode only. PostgreSQL mode intentionally mounts PostgreSQL-native routers and omitted the knowledge-search path, so the existing helper received HTTP 404 even though its token and status operation worked.

## Fix

PostgreSQL mode now registers a narrow compatibility router at the existing route. It uses the same Hermes authentication dependency and request/response schemas. SQLite keeps its existing route; both route handlers use one shared response serializer.

The PostgreSQL adapter searches active, non-archived archive.sources and archive.findings records using PostgreSQL simple full-text search with prefix terms. It shares the SQLite token selection and minimum-match filtering, bounds the requested result count, returns the established Hermes fields, and maps finding evidence to source IDs through finding_evidence and evidence.source_id. No migration, corpus write, alternate helper route, or second mobile interface is introduced.

## Changed paths

The complete baseline-relative patch covers:

- apps/api/src/research_terminal/api/routes/hermes.py
- apps/api/src/research_terminal/main.py
- apps/api/src/research_terminal/persistence/postgres_runtime.py
- apps/api/src/research_terminal/api/routes/hermes_knowledge.py (new)
- apps/api/src/research_terminal/services/hermes_knowledge.py (new)
- apps/api/tests/test_hermes_client.py
- apps/api/tests/test_postgres_pipeline.py
- docs/HERMES_POSTGRES_SEARCH.md (new)

The helper implementation itself needed no route change.

## Test and safety details

The PostgreSQL integration fixture uses only RESEARCH_TEST_POSTGRES_URL, which must point to a disposable database. The regression fixture creates its test roles and applies the local archive/ops schema chains. It omits 0017_public_registry_e007_e008.sql: that is a production Supabase promotion requiring the exact deployed Registry view and migration-role conditions, so it is not appropriate for a fresh local fixture. Migration 0015 creates a public projection outside the resettable schemas; fixture setup now removes only that exact view and its dedicated projection-owner role so the disposable fixture can run repeatedly.

Validation completed:

- apps/api/tests/test_postgres_pipeline.py against the same disposable Docker PostgreSQL 16 database: 13 passed, then 13 passed again after fixture reset.
- apps/api/tests/test_hermes_client.py apps/api/tests/test_retrieval_quality.py: 15 passed.
- apps/api/tests/test_hermes_client.py -k search: 4 passed.
- Ruff over all changed Python source and test paths: passed.
- The new PostgreSQL integration test checks unauthenticated rejection (401), authenticated success (200), source and finding mapping, and evidence-to-source IDs.
- A direct read-only check against the currently configured PostgreSQL corpus through the in-process app returned 200 and five results for Hermes; all five IDs were verified as existing active source/finding records. This exercised the current source code against the corpus, not the still-running deployed API process.

The Docker test database had no volume and was removed after each run. No live research jobs were enqueued; the integration suite used only the disposable Docker database. The previously observed API health had zero queued and zero running jobs. The inspected API startup and route registration require no schema migration and perform no corpus write for this change.

No actual credential was added to code or documentation; the route test uses only a fake fixture token. The existing token remains on the Studio and is read by the helper; it is never returned to the phone. No staging or commit was performed, preserving the existing dirty index and worktree.

## Deployment and remaining verification

The currently running launchd API process has not been restarted by this task. It will continue serving the old route set until the API is restarted with the updated source. After restart, validate using the existing helper with a harmless corpus query, then check the Hermes Orchestrator and live bridge path. Physical iPhone validation remains for the parent task.

No source commit hash exists for this patch. The Research Terminal checkout was already broadly dirty, so the patch is captured against the exact pre-edit worktree baseline rather than clean HEAD. Baseline SHA-256 values are in baseline-manifest.json.


## Parent deployment follow-up

The parent reloaded the live own-UID API under its existing launchd service with
zero queued/running jobs, then verified direct helper search, the HTTPS canonical
Orchestrator path, and a physical-phone invocation. All returned five real corpus
records and the same first source ID/title. Bridge/backend restart retained working
search. See `BOT_MODE_VALIDATION.md` in the Hermes iPhone checkout for final evidence
and the remaining phone bot/media validation gate. The source patch/index boundaries
above remain unchanged.

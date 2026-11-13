# apps/api: Jitter REST API

Hono on Node (TypeScript, strict). Serves `/api/v1/*`: auth/session, projects, documents,
assets (images, fonts), and font metadata. Postgres via Drizzle. Object storage is S3-compatible.

## Commands (run from `apps/api/`)

| Task | Command |
|---|---|
| Dev server | `pnpm dev` |
| Lint (auto-fix) | `pnpm lint --fix` |
| Format | `pnpm format` |
| Typecheck | `pnpm typecheck` |
| Test | `pnpm test` |
| DB migration (generate / apply) | `pnpm db:generate` · `pnpm db:migrate` |

## Conventions

- **Routes are thin.** `src/routes/` only parses input, calls a service and shapes the response.
  Business logic lives in `src/services/`. DB access lives in `src/db/` (Drizzle queries/repositories).
- **Every request and response is a zod schema imported from `@jitter/schema`.** Define routes with
  `@hono/zod-openapi` so validation and the OpenAPI document come from the same schema. Never
  declare an ad-hoc inline body type.
- **All I/O is `async`** (DB, storage, outbound HTTP). Never block the event loop with sync
  filesystem or CPU-heavy work. Heavy work (image processing, ML) belongs in a queue or `services/vision`.
- **Errors:** throw typed errors from services, and map them to HTTP responses in one error
  middleware with a consistent `{ error: { code, message } }` body (schema in `@jitter/schema`).
- **Auth:** every route requires a verified session, except those explicitly marked public.
  Authorize per resource (project ownership), not just per route.
- **Documents are opaque to the API except for validation:** validate with `@jitter/schema`'s doc
  schema on write, store as JSONB, and never re-shape them server-side. Pretext cannot run in Node,
  so the API never lays out text.
- Config comes from `src/env.ts` (zod-validated). Never read `process.env` elsewhere.
- Tests: Vitest. Route tests go through the Hono app (`app.request(...)`) against a test database.
  No mocking of the DB layer for route tests.

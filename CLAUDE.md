# Jitter

Visual drag-and-drop editor for text and image layouts, built on
[`@chenglou/pretext`](https://github.com/chenglou/pretext).

**`docs/SPEC.md` is the source of truth** for scope, decisions and architecture.
`docs/SCOPE.md` holds the background research and rationale behind it.

## Monorepo layout (TypeScript end-to-end, pnpm workspaces + Turborepo)

```
apps/
  web/            Next.js App Router (strict TS, Tailwind): marketing, auth, dashboard, editor shell
  api/            Hono REST API on Node, all routes under /api/v1/*
packages/
  schema/         zod schemas: the Jitter document format + API request/response contracts (single source of truth for types)
  engine/         pretext wrapper + layout pass. Framework-free, browser-only, no DOM writes
  render-dom/     RenderList → DOM projection (diffed writes)
  render-canvas/  RenderList → Canvas 2D
  runtime/        engine + renderers + behaviors; ships the web component and React wrapper
  editor/         editor UI (React, client-only), consumed by apps/web
  config/         shared tsconfig / eslint / prettier presets
services/
  vision/         (later, Python: FastAPI + uv) ML image segmentation. Not created yet
docs/
  SPEC.md         source of truth
  SCOPE.md        research and rationale
```

Directories are created as each phase needs them. Don't scaffold empty packages ahead of time.
Workspace-specific rules live in `apps/web/CLAUDE.md`, `apps/api/CLAUDE.md` and `packages/CLAUDE.md`.

## Cross-stack rules

- **Contracts live in `packages/schema` only.** Every API request/response body is a zod schema in
  `packages/schema/src/api/`. `apps/api` validates with it and generates OpenAPI from it. `apps/web`
  infers types from it. There is no hand-maintained duplicate of API types anywhere. Changing a
  contract means editing the schema, then fixing every type error both sides report.
- **REST under `/api/v1/*`.** Changes inside v1 must be additive (new optional fields, new routes).
  Breaking changes need a new version prefix.
- **The frontend never calls raw `fetch` in components.** It uses the typed client in
  `apps/web/src/lib/api/`, which parses responses with the shared schemas.
- **The document format is versioned.** Any change to `packages/schema/src/doc/` bumps
  `DOC_VERSION` and adds a migration in `packages/schema/src/doc/migrations/` with a test.
  Docs are stored and exported, so old ones must keep loading.
- **Dependency direction:** `schema` ← `engine` ← `render-*` ← `runtime` ← `editor` ← `apps/web`.
  `apps/api` depends only on `schema`. Nothing in `packages/` imports from `apps/`.
- **Secrets:** never read, write or commit `.env*` files. Each app validates its env with a zod
  schema in `src/env.ts`, which also documents the variables it needs.

## Workflow rules

1. **Read `docs/SPEC.md` before starting any new feature.** If the work conflicts with it, or
   isn't covered by it, stop and raise that before writing code. When a decision changes, update
   SPEC.md in the same change.
2. **Before finishing, run lint, typecheck and tests in every workspace you modified**, e.g.
   `pnpm --filter @jitter/engine lint typecheck test`, or `pnpm lint && pnpm typecheck && pnpm test`
   from the root for cross-cutting changes. Report failures honestly. Never skip or disable a test
   to get green.
3. **Changes to `packages/engine` or the renderers also run `pnpm --filter @jitter/engine bench`**,
   and must stay within the perf budget in SPEC.md §8.
4. A PostToolUse hook auto-runs eslint/prettier (TS) and ruff (Python) on edited files. Don't fight
   the formatter.

## Commands (root)

| Task | Command |
|---|---|
| Install | `pnpm install` |
| Dev (all) | `pnpm dev` |
| Lint / typecheck / test (all) | `pnpm lint` · `pnpm typecheck` · `pnpm test` |
| One workspace | `pnpm --filter <name> <script>` |
| Format | `pnpm format` |

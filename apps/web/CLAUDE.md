# apps/web: Jitter web app

Next.js App Router, strict TypeScript, Tailwind CSS. Hosts marketing pages, auth, the project
dashboard, and the editor route (which mounts `@jitter/editor`).

## Commands (run from `apps/web/`)

| Task | Command |
|---|---|
| Dev server | `pnpm dev` |
| Typecheck | `pnpm typecheck` (`tsc --noEmit`) |
| Lint | `pnpm lint` |
| Test | `pnpm test` (Vitest) · `pnpm test:e2e` (Playwright; pass `--trace off` unless debugging) |

## Conventions

- **Server Components by default.** Add `'use client'` only for components that need state,
  effects, event handlers or browser APIs, and push that boundary as far down the tree as possible.
- **The editor is client-only.** Pretext needs Canvas, so it cannot run during SSR. Load the editor
  and any `@jitter/runtime` preview with `next/dynamic(..., { ssr: false })`. Never import
  `@jitter/engine` from a Server Component.
- **Strict TypeScript:** no `any`, no `@ts-ignore` / `@ts-expect-error`, and no non-null `!` on
  external data. Narrow `unknown` with zod instead.
- **Validate with zod:** env vars in `src/env.ts` (server and public split, parsed at startup).
  Forms use zod schemas, shared with the API from `@jitter/schema` when the form maps to an API body.
- **Data access goes through `src/lib/api/`** (typed client built on `@jitter/schema`). No raw `fetch`
  in components. Server Components call the client directly. Client Components use it via hooks in
  `src/lib/api/hooks/`.
- **Tailwind for app chrome only.** The editor stage and runtime output are styled by the engine and
  renderers, not Tailwind classes.
- **Performance:** never re-render the editor stage through React state at 60 fps. The stage
  subscribes to the store outside React (see `packages/CLAUDE.md`).

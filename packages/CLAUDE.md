# packages/: shared libraries

`schema`, `engine`, `render-dom`, `render-canvas`, `runtime`, `editor`, `config`.
`engine` and the renderers are the performance-critical core. Read SPEC.md §4 and §8 before changing them.

## Commands (run inside a package, or `pnpm --filter @jitter/<name> <script>` from root)

| Task | Command |
|---|---|
| Lint / typecheck | `pnpm lint` · `pnpm typecheck` |
| Test | `pnpm test` (Vitest. Engine/renderer tests run in **browser mode** via Playwright Chromium, since Pretext needs Canvas) |
| Benchmark (engine, renderers) | `pnpm bench` |
| Build | `pnpm build` |

## Rules

### schema
- zod is the single source of truth for the document format and API contracts. Export inferred
  types (`z.infer`) and never hand-write a parallel interface.
- Doc changes bump `DOC_VERSION` and add a tested migration. Nodes are stored in an **id-keyed map**
  (never identified by array index), so the format can move to a CRDT later.

### engine
- **Framework-free and DOM-free:** no React, and no reading or writing the DOM. Its only browser
  dependency is Canvas measurement via Pretext.
- **Pretext is imported only inside `src/text/`.** Everything else goes through that wrapper, so an
  upstream API change touches one place.
- **`layoutScene(doc, env, t) → RenderList` is pure.** The same inputs give the same output, with no
  hidden mutable state except explicit caches.
- **Never call `prepare*()` on the hot path.** Prepare only on *metric* changes (text, font, size,
  weight, style, case, tracking). Paint-only changes (color, opacity, decoration, fills) must not
  re-prepare or re-layout.
- Text case is applied to the string before `prepare` (Pretext doesn't model `text-transform`).
  Tracking is stored in em and converted to px at prepare time. Fonts are explicit named stacks,
  never `system-ui`.
- Prepare only after the font manager reports the face loaded (`document.fonts.load(font, text)`).
  Call `clearCache()` deliberately on font load, `lang` change or DPR change.
- No per-frame allocations in inner loops (band/slot iteration). Reuse arrays.

### renderers
- Consume `RenderList` only. Diff and write only what changed. Use transforms rather than
  top/left. Containers use `contain: strict`.
- The canvas renderer must emit an accessible, visually-hidden DOM text mirror in reading order.

### editor
- The stage is driven by the store and engine outside React. React renders panels and inspectors
  only, and subscribes with selectors.
- Edits are patches on the normalized doc. A continuous gesture (a drag) coalesces into one undo entry.

### general
- Strict TS: no `any`, no `@ts-ignore`. Public package APIs get explicit return types.
- Packages never import from `apps/`.

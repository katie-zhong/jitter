# Jitter: Specification

> **Source of truth.** Read this before starting any feature. Update it in the same change when a
> decision changes. Background research and rationale are in [`SCOPE.md`](./SCOPE.md).
>
> Status labels: **Decided** = agreed with the product owner. **Proposed** = recommended in planning
> and not yet confirmed. **Open** = needs a decision.

---

## 1. Product

Jitter is a visual drag-and-drop editor for expressive text and image layouts: editorial
compositions, text flowing around and inside shapes and images, and typographic effects. It is built
on [`@chenglou/pretext`](https://github.com/chenglou/pretext) (MIT, v1.0.0, pinned). Pretext measures
text and computes line breaks without DOM reflow.

| Item | Decision | Status |
|---|---|---|
| Audience | Designers who work with code (e.g. via Figma MCP) and frontend engineers | Decided |
| Top priorities | 1. Editorial engine. 2. Variable typographic ASCII. 3. Dynamic layout | Decided |
| Next major feature | Combining images with text (§6) | Decided |
| Outputs | Standalone HTML, web component (`<jitter-scene>`), React component (all three) | Decided |
| Render targets | DOM **and** canvas | Decided |
| Breakpoints | In v1 | Decided |
| Accounts and cloud save | Yes, as its own phase after a local-first MVP. Multiplayer later, but the data model must allow it | Decided |
| Fonts | Google Fonts picker in v1. User uploads later | Decided |

---

## 2. Tech stack

| Layer | Choice | Status |
|---|---|---|
| Language | **TypeScript end-to-end** (strict) | Proposed (replaces the initial Python/FastAPI + Next.js idea, see below) |
| Monorepo | pnpm workspaces + Turborepo | Proposed |
| Web app | Next.js App Router, Tailwind CSS (app chrome only) | Decided |
| Editor UI | React (panels only), stage driven by engine outside React | Proposed |
| API | Hono on Node, REST under `/api/v1/*`, `@hono/zod-openapi` | Proposed |
| Contracts and doc format | zod in `packages/schema` (single source of truth) | Proposed |
| Database / storage / auth | Postgres (Drizzle), S3-compatible storage, managed auth. Supabase is the suggested provider | Proposed |
| Tests | Vitest (browser mode for engine/renderers), Playwright e2e | Proposed |
| ML vision (later) | Python `services/vision` (FastAPI, uv, ruff, mypy) | Proposed, deferred |

**Why TypeScript end-to-end instead of a Python backend:**
1. **The product's core is client-side.** Pretext needs a browser Canvas, so layout runs only in the
   browser. The engine and its runtime are TypeScript no matter what. The v1 backend is thin:
   auth, project CRUD, doc storage and asset upload.
2. **One schema, zero drift.** The document format must be validated identically in the editor,
   the exported runtime and the API. A zod schema shared by all three removes the need for a
   hand-synced `api.ts` mirror of Pydantic models, a classic source of silent bugs.
3. **Performance isn't decided by the backend language.** API load is CRUD and blob storage. The
   real performance budget is in the browser (§8).
4. **One toolchain** (pnpm, eslint, prettier, vitest) means less setup, faster CI and simpler hooks.
5. **Python still earns a place later** for ML image segmentation (§6), as an isolated service.

**Why a separate API instead of Next.js route handlers:** exported components, a future MCP/agent
API and CLIs need a stable public API that doesn't depend on the web app's deployment, and it can
scale on its own.

---

## 3. Pretext constraints that shape the design

These are requirements, not suggestions (details in SCOPE.md §1–2):

1. Text is prepared only after its web font has loaded (`document.fonts.load(font, sampleText)`).
   Call `clearCache()` deliberately on font load, `<html lang>` change and DPR change.
2. Fonts are **explicit named stacks**: primary, then script fallbacks, then an emoji font. Never
   `system-ui` or a generic-only stack.
3. No `text-transform`: case is applied to the string before preparing, with a source↔display
   offset map.
4. Letter spacing is px-only: store tracking in em and convert at prepare time.
5. No server-side layout (Canvas required). Exports are client-rendered. SSR ships a semantic text
   fallback.
6. Per-letter effects are reliable only for Latin, Greek, Cyrillic and CJK. Complex scripts and bidi
   text degrade to line-level effects. Bidi text is best on the DOM renderer.
7. No built-in justification or auto-hyphenation: these are Jitter features.
8. Pretext's API review is pending upstream: the version is pinned and all calls are wrapped in
   `packages/engine/src/text/`.

---

## 4. Architecture

```
Doc (JSON, zod-validated) → resolve(breakpoint, constraints, units) → behaviors.step(dt)
  → layout pass (pure) → RenderList → render-dom | render-canvas
```

- `layoutScene(doc, env, t) → RenderList` is a pure function and also the shipped runtime.
- **Metric vs. paint attributes:**
  - Metric changes (text, font, size, weight, style, case, tracking) re-prepare.
  - Paint changes (color, decoration, opacity, fills, per-glyph transforms) never re-prepare
    or re-layout.
- **Shapes** are polygons with holes. Sources: rect, ellipse, path, glyph outline, image alpha,
  image threshold mask, and later ML. They can be offset with a real polygon offset (Clipper).
- **Regions vs. obstacles.** Regions are where text may go and obstacles are where it may not. Per
  line band: allowed = region intervals − obstacle intervals, then carved into slots. This uses
  **multi-interval scanlines**: the demo's single-span polygon interval loses holes and isn't enough.
- **Rotated frames** are laid out in local coordinates.
- **Stories thread through frames** via the cursor chain. Overflow policy per story: grow, clip,
  ellipsis, continue, or shrink to fit.
- **Behaviors** (physics, spin, tween, triggers, per-letter animation) are separate from nodes, so
  new visual features plug in without engine changes.
- **Doc storage:** normalized, id-keyed nodes and patch-based edits, so it stays CRDT-compatible
  (Yjs) for multiplayer later. The doc format is versioned with migrations.

Node types (initial): `Frame`, `Story`, `FitText`, `Obstacle`, `Image`, `DropCap`, `PullQuote`,
`AsciiField`, plus containers (`free`, and later `flow`).

---

## 5. Text and font system

```ts
Story → Paragraph[] → Run[] (text + styleRef + overrides)
TextStyle = metric { family, weight, italic, size, lineHeight, trackingEm, case }
          + paint  { color | gradient | imageFill, decoration, opacity, highlight/shape }
FontStack = [primary, ...scriptFallbacks, emojiFont]
```

- A single-style paragraph uses `prepareWithSegments` / `layoutNextLine`. Mixed runs use
  `prepareRichInline` / `layoutNextRichInlineLineRange`, which also stream line by line and work
  with obstacle flow. Line height per line comes from run font metrics.
- **v1:** Google Fonts family and weight, italic, size, line height, tracking, case
  (upper/lower/title), color, bold/italic runs, and emoji and accented text via proper stacks.
- **Later:** gradients and image fills, OpenType features, custom variable axes (named instances
  only), true small caps, and font uploads.
- The Google Fonts catalog comes from a build-time snapshot (no runtime API key). Fonts load through
  the CSS2 API with sample text, so `unicode-range` subsets load.

---

## 6. Feature catalog

### 6.1 Priority demos (parity targets)
- **Editorial engine:** frames with columns, story threading and overflow badges, a fit-text
  headline, drop cap, pull quotes as obstacles, circle/rect obstacles, a physics behavior, and edit
  vs. play modes.
- **Dynamic layout:** image nodes with alpha-derived hulls (separate layout and hit hulls, with an
  overlay preview), polygon editing, rotation, spin/tween on click or hover.
- **Variable typographic ASCII:** `AsciiField` = grid + pluggable brightness source (particles,
  fluid, image, video, webcam, node render) + palette (family, charset, weights, styles, error
  weights, invert, color). The palette is built in idle time, cached, and baked into exports.

### 6.2 Images × text
| Feature | Technique |
|---|---|
| Text inside visual areas (glyph outlines, shapes, image areas) | Region shapes + multi-interval scanlines. Rotated frames for vertical words |
| Auto-suggested areas | Tier 1: alpha channel + luminance/color threshold + connected components. Tier 2 (later): ML segmentation in `services/vision` or in the browser |
| Text blocks with image wrap | Images as obstacles (rect or hull), per-image padding and offset shape |
| Templated image/text distribution ("2D block editor") | Flow/stack/grid containers. Solver justifies rows using exact `layout()` heights. Masonry |
| Images inside lines of text | Rich-inline `{ width }` boxes + per-line justification |
| Text colored by an image | `background-clip: text` (DOM) or `source-in` compositing (canvas). Posterized per-word sampling |
| Shape superposition | Decorations painted behind or over fragments using rich-inline fragment geometry. Inline shape boxes |
| Whitespace/negation from images | Layout mode (mask becomes an obstacle) or paint mode (knockout glyphs) |
| Curved text and per-letter animation | Text on path by arc length (prefix-measured advances). Multi-line offset curves. Per-letter behaviors. Canvas/SVG for large glyph counts |
| Custom break shapes around images | Obstacle = shape + offset + optional visible keep-out fill/overlay |

---

## 7. Responsive layout (Proposed: hybrid)

The problem has six dimensions: geometry, typography, structure, content overflow and page
height, media, and embedding (component width ≠ window width).

- **Containers:** `free` (absolute children with constraints), and `flow` (stack/grid, after the MVP).
- **Constraints** in free containers: pin left/right/center/stretch/scale, with min/max.
- **Breakpoints** are **container-width** ranges. Every property is `base + sparse overrides`,
  cascading desktop-first. The UI shows overrides and offers "reset to base".
- **Units:** px, %, `cqw`/`cqh`, and `clamp(min, fluid, max)`. Expressions are an escape hatch for engineers.
- **Scale-to-fit** page mode for posters (uniform scale, no relayout).
- **Page height mode:** fixed / content / viewport. **Overflow policy** per story.
- **v1 scope:** free containers, constraints, units, breakpoints with overrides for position, size,
  visibility, font size, columns and obstacle scale, scale-to-fit, and both height modes.

---

## 8. Performance budget (a core requirement)

- **Frame budget:** 16.7 ms (60 Hz) for layout + DOM commit + paint during drags and animation.
  Targets: **≤ 4 ms layout, ≤ 4 ms commit** on a mid-range laptop, and ≤ 2× that on a mid-range phone.
- **Reference scene** (CI perf gate, from Phase 0): 3 columns, 6 obstacles including 2 polygons,
  and a 2,000-word story.
- **Rules:**
  - `prepare` never runs per frame. Prepare per paragraph.
  - Paint-only changes skip layout.
  - Diff DOM writes. Use transforms and `contain: strict`.
  - Use simplified hulls with bounding-box rejection. Coarse while dragging, refine on idle.
  - Do pixel work (hulls, palettes, sampling) at import or in idle time, cached and baked into exports.
  - The stage is outside React. A drag is one undo entry.
- **Renderer choice:** DOM by default for text (accessibility, selection, bidi). Canvas for
  effect-heavy nodes (ASCII, per-letter, high glyph counts), with a hidden semantic text mirror.
- The engine stays pure so layout *can* move to a worker later (with the macOS emoji-width caveat).

---

## 9. Outputs and integration

- `@jitter/runtime` = engine + renderers + behaviors. It ships as:
  - a standalone HTML export (runtime + inlined doc + font links);
  - a web component (`<jitter-scene src="…">` or a `doc` property);
  - a React component (`<JitterScene doc={…} />`).
- All are client-rendered. SSR/no-JS gets semantic text in reading order.
- Exports set `<html lang>`, include font loading, and bake precomputed hulls and palettes.
- **Later:** PNG/video export from the canvas renderer, content binding/slots for engineers, a
  Figma importer, and a Jitter MCP/agent API over the doc format.

---

## 10. Accounts and cloud

- MVP is local-first (IndexedDB).
- The cloud phase (about 3–4 engineer-weeks, including font uploads) covers auth, projects,
  autosave of doc JSON, and asset storage. Sharing links and version history add about 1 week each.
- Multiplayer later: Yjs + a hosted provider (about 3–5 weeks), enabled by the id-keyed, patch-based doc model.
- Uploaded fonts: the user is responsible for embed licensing. Exports ship the font file.

---

## 11. Roadmap (one-engineer estimates)

| Phase | Scope | Est. |
|---|---|---|
| 0. Engine spike + perf harness | Doc schema v0 with value/override types; frames, threading, circle/rect/polygon obstacles with multi-interval scanlines, regions, fit text; DOM renderer; editorial demo rebuilt from JSON; perf gate | 2–3 wk |
| 1. Editor MVP | Stage (pan, zoom, select, transform, snap), layers, inspector, story panel with runs, Google Fonts and font manager, breakpoints, constraints, scale-to-fit, undo, IndexedDB save, all three export forms | 7–9 wk |
| 2. Priority demos at parity | Editorial, dynamic layout, ASCII field. Canvas renderer v1 | 5–7 wk |
| 3. Accounts and cloud *(parallel to 2)* | Auth, projects, autosave, assets, font uploads | 3–4 wk |
| 4. Images × text | §6.2 except curved/kinetic. Flow containers and justified distribution | 6–8 wk |
| 5. Kinetic type | Text on path, per-letter behaviors, PNG/video export | 4–6 wk |
| Later | ML segmentation, multiplayer, Figma import, MCP/agent API, content binding, OpenType features, version history | — |

---

## 12. Open questions

1. Confirm the **TypeScript end-to-end stack** (§2) over Python/FastAPI.
2. Confirm the **responsive hybrid model** (§7).
3. The default height model for web exports: viewport poster or scrolling article?
4. Content binding (slots fed by props/CMS) in v1?
5. Figma import priority (it affects how closely nodes mirror Figma frames and Auto Layout)?
6. Team size and timeline target?
7. The auth/DB provider (Supabase suggested)?

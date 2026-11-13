# Jitter — a visual editor for Pretext

Scope for a drag-and-drop editor that composes layouts powered by
[`@chenglou/pretext`](https://github.com/chenglou/pretext) (MIT, v1.0.0).
First targets: **editorial engine**, **variable typographic ASCII**, **dynamic layout**.
Built so more visual features can be added later as plug-in node types.

---

## 1. What Pretext gives us (and what it doesn't)

Pretext is a measurement + line-breaking library. It does **not** render or compose pages.

| API | Use in the editor |
|---|---|
| `prepare` / `prepareWithSegments(text, font, {letterSpacing, whiteSpace, wordBreak})` | One-time, cached per (text, font, options). Never re-run on drag. |
| `layout(prepared, width, lineHeight)` | Cheap height checks: fit-to-box, binary searches. |
| `layoutWithLines` | Fixed-width blocks (pull quotes, headlines). |
| `layoutNextLine` / `layoutNextLineRange` + `LayoutCursor` | **The core primitive.** Variable width per line: lets text flow around obstacles and *thread* across columns/frames by passing the cursor along. |
| `walkLineRanges`, `measureLineStats`, `measureNaturalWidth` | Shrink-wrap, balanced text, glyph widths for ASCII palettes. |
| `rich-inline` | Mixed fonts / inline chips (later phase). |

Everything else seen in the demos is **demo code we must reimplement/extract**:
obstacle → band-interval math (`circleIntervalForBand`, `getPolygonIntervalForBand`,
`getRectIntervalsForBand`), `carveTextLineSlots`, image-alpha wrap hulls (`getWrapHull`),
headline fitting, DOM line projection with diffing (`line-nodes.ts`), orb physics,
the ASCII brightness palette, and the particle field.

### The shared pattern across all three demos

```
Scene (objects + params) ──► layout pass (pure, per frame) ──► RenderList ──► DOM projection (diffed)
          ▲                                                                       │
          └──────────── interaction / behaviors (drag, physics, spin) ◄───────────┘
```

The editor's job is to make the **Scene** editable and serializable, and to generalize the
**layout pass** into a reusable engine. The same engine runs in the editor and in exported pages.

---

## 2. Architecture

Three packages (monorepo):

1. **`@jitter/engine`**: framework-free TS. `layoutScene(doc, viewport, time) → RenderList`.
   Pure function over a JSON document. Owns the prepare-cache, obstacle geometry, text threading,
   fit-text, ASCII field. No editor code. **This is also the export runtime.**
2. **`@jitter/renderer-dom`**: projects a `RenderList` to absolutely-positioned DOM lines
   (selectable, accessible text), diffing like the demos do. Canvas renderer later if perf demands.
3. **`@jitter/editor`**: the app. Stage + selection/transform overlay, layers, inspector,
   asset library, undo/redo, persistence, export.

Recommended stack: TypeScript, Vite, React for editor chrome only (the stage is engine-driven,
not React-rendered), an immutable doc store with patch-based undo (e.g. Immer patches),
and Bun/Vitest + Playwright for tests.

### Document model (sketch)

```ts
type Doc = { version: 1; pages: Page[]; assets: Asset[]; fonts: FontRef[] }
type Page = { id; size: { w; h } | 'viewport'; breakpoints: Breakpoint[]; nodes: Node[] }

type Node =
  | Frame        // rect region, columns, columnGap; belongs to a Story's thread
  | Story        // text + style; ordered list of Frame ids it flows through (threading)
  | FitText      // headline: text, font family/weight, min/max size, "no in-word break"
  | Obstacle     // shape: circle | rect | polygon | imageHull; padding h/v; wrapSide
  | ImageNode    // asset + optional derived wrap hull (alpha), rotation
  | DropCap      // attached to a Story: lines, font
  | PullQuote    // composite: text block that is also a rect obstacle
  | AsciiField   // grid + source + palette (see §3.2)

// Every node: id, name, transform {x,y,w,h,rotation}, constraints, behaviors[]
type Behavior = { type: 'physics' | 'spin' | 'drag' | 'hover' | ...; params }
```

Behaviors are kept separate from nodes, so new motion and interaction can be added
without touching layout.

### Layout pass (engine)

1. Resolve the active breakpoint and node transforms (constraints → absolute rects).
2. Step behaviors (physics, spin) given `dt`.
3. Lay out fixed-size blocks first: FitText, PullQuotes, DropCaps, which become obstacles.
4. For each Story: walk its Frames → columns → line bands; per band collect blocked
   intervals from all obstacles intersecting the frame, carve slots, call `layoutNextLine`
   per slot, carry the cursor to the next band/column/frame. Report **overflow** if text remains.
5. Lay out AsciiFields (independent of text flow, unless marked as obstacles).
6. Emit `RenderList` (positioned lines with font, shapes, images, ASCII rows).

---

## 3. Priority features → editor features

### 3.1 Editorial engine

Demo has: auto-fit headline, multi-column body, drop cap, pull quotes as rect obstacles,
draggable/animated circle obstacles ("orbs") with physics, narrow-viewport variant.

| Editor capability | Notes |
|---|---|
| Draw **Frames**, set columns/gap | Columns = sub-regions the cursor threads through. |
| **Thread** Story across frames (InDesign-style in/out ports) | Cursor-passing makes this nearly free; the UI is the work. Overflow indicator. |
| **FitText** headline node | Binary search on size like `fitHeadline`; inspector: min/max size, letter-spacing, line-height ratio. |
| **Drop cap** toggle on a Story | Rect obstacle sized from `measureNaturalWidth`. |
| **Pull quote** node | Positioned by column + y-fraction, or freely; is an obstacle. |
| **Obstacles**: circle / rect, padding, wrap mode | Wrap mode: both sides (all slots) vs. largest slot only (demo's narrow mode). |
| **Physics behavior** | Velocity, bounce bounds, mutual repulsion, click-to-pause. |
| Live reflow while dragging | Core UX. Only `layout*` runs per frame; `prepare` is cached. |

### 3.2 Variable typographic ASCII

Demo has: a brightness field (particles + attractors splatted into a grid), mapped per cell
to the glyph whose **measured brightness and width** best match. Palette = charset × weights ×
styles in a proportional font, measured with Pretext + canvas pixel sampling. Mono-ramp
comparison alongside.

| Editor capability | Notes |
|---|---|
| **AsciiField** node: cols, rows, font size, line-height, target row width | Resizable on the stage. |
| **Source**: particles sim (demo), image, video, webcam, gradient/noise, *another node's render* | Pluggable `BrightnessSource` interface → `Float32Array` field. |
| **Palette**: font family, charset, weights, styles, brightness/width error weights, invert, color/alpha mapping | Palette build is costly (canvas reads); cache per (font, charset, weights, styles). Do it in an idle callback with a progress state. |
| Mode: proportional vs. mono ramp | |
| Source params exposed in inspector (particle count, attractor forces, decay) | |
| Export as live HTML, or frozen text/SVG/PNG frame | |

### 3.3 Dynamic layout

Demo has: two-column spread, headline + credit, body text wrapping around **image logos using
alpha-derived polygon hulls** (separate hull for layout vs. hit testing), click-to-spin rotation
with easing, text reflowing every frame, narrow variant.

| Editor capability | Notes |
|---|---|
| **ImageNode** with "wrap to shape" | Compute hull from alpha (`mean`/`envelope`, smoothing radius, convexify) in the inspector, with a hull overlay preview. Needs same-origin/CORS-clean images. |
| Manual **polygon** obstacle / editable hull points | Fallback when alpha isn't usable. |
| **Rotation** of obstacles | `transformWrapPoints` already handles it. |
| **Spin / tween behaviors** triggered by click/hover | Small timeline: trigger → property tween → easing. |
| Text in spreads/columns wrapping obstacles that cross column boundaries | Falls out of §2 step 4. |

---

## 4. Cross-cutting concerns & risks

1. **Fonts**: Pretext measures with canvas; text must be measured after the webfont loads, and
   the CSS font string must match exactly. The editor needs a font manager: load via
   `document.fonts.load`, then invalidate the prepare-cache and relayout. Variable/weight
   fonts must actually have the weights the ASCII palette uses. Avoid `system-ui` as a measured
   font.
2. **Responsive layout is the hardest design problem.** The demos hard-code their narrow
   variants with magic numbers. We need a constraints model (anchors, % / vw units, min/max)
   **plus** per-breakpoint overrides (hide node, change columns, scale obstacles). Decide early;
   it shapes the doc schema.
3. **Performance budget**: 60fps reflow while dragging, with ~3 columns, ~5 obstacles, and polygon
   hulls (polygon band sampling is per-pixel-row; cache per band or simplify hulls). Keep
   `prepare` off the hot path; diff DOM writes as `line-nodes.ts` does.
4. **Editing text**: v1 edits story text in an inspector/side panel (plain text + paragraph
   breaks). Inline on-canvas editing of flowed text (caret across threaded frames) is
   expensive; defer it.
5. **Editor interaction vs. live behaviors**: an edit mode (behaviors frozen, handles on) vs.
   a play mode (behaviors run, the page's own interactions active).
6. **Pretext API churn**: 1.0.0, but an API review is pending upstream (TODO.md). Pin the version
   and wrap it behind `@jitter/engine` so changes stay in one place.
7. **Extracting demo code**: `wrap-geometry.ts` etc. aren't in the npm package. Port them into
   the engine with attribution (MIT).
8. **Accessibility/SEO of exports**: line-split DOM fragments text. Also emit the full story text
   in reading order (visually hidden or `aria-label`) in exports.

---

## 5. Phased plan

| Phase | Scope | Exit criteria |
|---|---|---|
| **0. Engine spike** | Doc schema v0; engine with Frames, Story threading, rect/circle obstacles, FitText; DOM renderer. Rebuild the editorial demo **from a JSON file**. | Editorial demo reproduced from JSON at 60fps. |
| **1. Editor MVP** | Stage with pan/zoom, select/move/resize/rotate, snapping; layers panel; inspector; toolbar to drag in nodes; story text panel; threading UI + overflow badge; undo/redo; save/load JSON (local); export standalone HTML (engine runtime + doc). | A user builds a 2-column article with a headline and obstacles without code. |
| **2. Editorial parity** | Drop cap, pull quotes, physics behavior, edit/play modes, font manager, breakpoints v1. | Editorial demo fully re-creatable in the editor. |
| **3. Dynamic layout parity** | ImageNode, alpha hulls + overlay, polygon editing, spin/tween behaviors on click/hover. | Dynamic-layout demo re-creatable. |
| **4. Typographic ASCII** | AsciiField, particle + image/video sources, palette inspector, export modes. | ASCII demo re-creatable; image → ASCII works. |
| **5. Extensibility** | Public node/behavior/source plugin API; rich-inline text; more demos (bubbles, masonry, ellipsis, justification). | A new node type ships without engine changes. |

Phases 3 and 4 are independent once Phase 1 lands and can run in parallel.

---

## 6. Open decisions

1. **Audience**: designers (Figma-like, no code) or developers (output is a component/JSON they embed)? This changes export and how much of the code we expose.
2. **Output**: standalone HTML page, embeddable `<jitter-scene>` web component, React component, or all three?
3. **Fixed page vs. responsive canvas**: should v1 support breakpoints, or only fixed-size art boards?
4. **Persistence/collab**: local files only, or accounts and cloud save? Realtime multiplayer later?
5. **Fonts**: Google Fonts picker, user uploads, or both? (Affects licensing and measurement.)
6. **Render target**: DOM only (selectable text), or also canvas/SVG export for video/print?

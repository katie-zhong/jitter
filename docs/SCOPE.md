# Jitter: a visual editor for Pretext

Scope for a drag-and-drop editor that composes text-and-image layouts on top of
[`@chenglou/pretext`](https://github.com/chenglou/pretext) (MIT, v1.0.0).

**Top priorities:** the editorial engine, variable typographic ASCII, dynamic layout.
**Next:** combining images with text (text inside image regions, multi-image wrap, visual text effects).
**Audience:** designers who work with code (e.g. through Figma MCP) and frontend engineers.
**Outputs:** standalone HTML, a web component, and a React component.
**Render targets:** DOM and canvas.

---

## 1. Pretext primer

### What the DOM is
The **DOM** (Document Object Model) is the browser's live tree of objects for a page: elements
like `<div>` and `<p>`, and the text inside them. JavaScript reads and changes that tree. The
browser takes the tree plus CSS and computes *layout*: where every box and line goes. Then it paints.
If JavaScript asks for a size (`offsetHeight`, `getBoundingClientRect`) after something changed,
the browser has to stop and recompute layout synchronously. That is a **reflow**, and it's one
of the most expensive things a page can do. Doing it in a loop ("layout thrashing") is how pages stutter.

### How Pretext works
1. **`prepare(text, font)`** (slow, run once): splits the text into segments at break opportunities
   (words, spaces, CJK characters, emoji) with Unicode rules and `Intl.Segmenter`, then measures each
   segment's width using canvas `measureText`. Canvas uses the browser's own font engine, so the widths
   match what the browser would paint. Returns an opaque handle.
2. **`layout(handle, width, lineHeight)`** (fast, run as often as needed): pure arithmetic over the
   cached widths. It re-implements CSS line breaking in JavaScript, including per-browser quirk
   profiles for Blink, Gecko and WebKit, so the line breaks match the browser's exactly. No DOM involved.
3. **`layoutNextLine(handle, width, cursor)`**: the same thing one line at a time, with a different
   width for each line. This is what makes flowing text around shapes and threading text across frames possible.

### Does it break from HTML/CSS?
It has two modes, and only the second departs from the standard:

- **Measure-only (standards-compliant).** Pretext predicts a paragraph's height, and the browser still
  wraps and paints the text normally. It's just CSS without the reflow.
- **Manual line layout (a departure).** You take line breaking away from the browser. Each line becomes
  its own absolutely-positioned element, or a canvas `fillText` call, at coordinates you computed. This is
  what makes text-around-shapes possible, and CSS has no equivalent beyond rough `shape-outside` floats.
  The cost is that you now own things the browser normally handles:
  - **Selection and copy** across lines are fragmented. The demos handle this with care.
  - **Accessibility.** Screen readers see line fragments, not paragraphs.
  - **Reflow on zoom or user font-size changes**, find-in-page, and SEO.
  - **Justification and hyphenation.** Neither is built in. You insert soft hyphens yourself.
  - **Bidi (mixed left-to-right/right-to-left) visual order** on canvas.
  - **Only a subset of CSS text features** is supported: `white-space: normal | pre-wrap`,
    `word-break: normal | keep-all`, `overflow-wrap: break-word` (required), and `letter-spacing` in px
    only. `text-transform`, `font-feature-settings`, custom variable-font axes and `system-ui` are not modeled.

**Rule for Jitter:** anything that changes glyph widths has to be known to Pretext. Anything that
doesn't (color, opacity, underline, shadows) is free to change.

---

## 2. README findings that matter for Jitter

| # | Finding | Consequence for Jitter |
|---|---|---|
| 1 | Text must be prepared **after** its web font loads. Use `document.fonts.load(font, text)` *with the text*, because Google Fonts splits families by `unicode-range`. `document.fonts.ready` is not enough. Safari: add the `FontFace` before it loads, or call `clearCache()`. | The font manager owns loading, and invalidates and re-prepares when a font arrives. |
| 2 | Use named fonts by their English family name. `system-ui` and `-apple-system` are inaccurate on macOS. Missing glyphs fall back to a font Pretext didn't measure. | Every text style resolves to an explicit **font stack**: primary font, a script fallback per language, and an emoji font. No generic-only stacks. |
| 3 | `<html lang>` changes line breaks and fonts. Changing it requires re-preparing. | `lang` is a document property, and the export sets it. |
| 4 | **No `text-transform`.** CSS uppercase would measure the wrong string. | Apply case to the string *before* `prepare`, and keep a source↔display offset map (`ß`→`SS`, Turkish `i`). |
| 5 | `letterSpacing` is px only. | Store tracking in em, and convert per font size at prepare time. |
| 6 | Rich inline (`prepareRichInline`) handles mixed fonts, chips and inline boxes, and streams line by line. Heights are yours: mixed sizes make a line taller, and painting must use `line-height: 1` per fragment. | Rich inline is the basis for bold/italic/size runs and inline images. The engine computes per-line height from the run fonts' ascent and descent. |
| 7 | `{ width }` boxes inside rich inline act like `<img>` inside a line. | Inline images and shapes inside text, like the "36 ways" poster (§6). |
| 8 | Segment widths can't position individual characters in Arabic or bidi text. Pretext gives no visual order, and canvas orders each line as its own paragraph. | **Per-letter effects** (curves, animation) are reliable for Latin, Greek, Cyrillic and CJK only. Restrict or degrade them for complex scripts. Bidi text renders best through the DOM renderer. |
| 9 | **Needs a Canvas 2D context.** It throws in Node, Bun or jsdom. | **No server-side layout.** React and web-component outputs are client-rendered. SSR has to ship a semantic text fallback or a pre-baked layout at a known width. |
| 10 | Works in a Worker with `setLocale`, but small emoji measure too wide there on macOS. | A layout worker is possible later, with an emoji caveat. |
| 11 | On macOS, emoji width depends on `devicePixelRatio`. | Call `clearCache()` and re-prepare emoji text when the DPR changes (e.g. the window moves to another monitor). Editor zoom must be a CSS transform, not browser zoom. |
| 12 | Global segment cache, which is dropped whole past 262k segments. | An editor that cycles through many fonts can hit sudden cache flushes. Track it, and call `clearCache` deliberately. |
| 13 | No justification, no auto-hyphenation. The `justification-comparison` demo shows a userland approach. | Justify and hyphenate are our features to build. |
| 14 | Public API review is pending upstream. | Pin the version, and wrap Pretext behind `@jitter/engine`. |

The **community demos** (`somnai-dreams/pretext-demos`) are mostly bundled copies of the official
demos. Two are new:
- `fluid-smoke` drives the ASCII field from a fluid simulation. This confirms the ASCII
  **brightness source** should be pluggable.
- `shrinkwrap-showdown` binary-searches widths with `walkLineRanges` for balanced chat bubbles.
  This gives us balanced and shrink-wrapped text boxes.

---

## 3. Decisions and their implications

| Decision | Implication |
|---|---|
| **Audience:** designers who work with code, and frontend engineers | Treat the doc JSON as a product surface: typed, versioned and human-readable. Engineers will want **content binding** (story text and images from props or a CMS) and **slots**. Later, an MCP server or agent API lets Claude/Figma-MCP workflows create and edit Jitter docs. A Figma importer goes on the roadmap. |
| **Outputs:** HTML, web component and React | One runtime (`engine` + `renderer`). The web component `<jitter-scene src|doc>` wraps it, React wraps the same runtime, and HTML is the runtime plus the inlined doc. All are client-rendered (§2 #9). |
| **Breakpoints in v1** | The schema supports override layering from day one (§7). This adds about 2–3 weeks to v1. |
| **Accounts and cloud save** | A BaaS such as Supabase (auth, Postgres, storage) is about **2–3 engineer-weeks** for auth, projects list, autosave of doc JSON, and image/font asset upload. Sharing links and permissions add about 1 week. Version history adds about 1 week. Hosting cost is low until there is real usage. **Keep multiplayer possible:** use an id-keyed normalized doc (no array-index identity) and patch-based edits, so it maps onto Yjs later. Real-time multiplayer would then be about 3–5 weeks (Yjs plus a hosted provider such as Liveblocks or y-sweet). Ship local-first (IndexedDB) in the MVP, and add cloud as its own phase. |
| **Fonts: Google first, then uploads** | Google Fonts picker: **about 1.5–2 weeks** (search, previews, weights and styles, CSS2 API loading, font manager). Metadata comes from a build-time snapshot of the Google Fonts Developer API, so no key is shipped. Uploads: **about 1–2 weeks** after cloud exists (read name tables and axes with fontkit or opentype.js, store in object storage, `FontFace` loading). Users are responsible for embed licensing, and the export must ship the font file. |
| **Render to DOM and canvas** | The renderer interface consumes a `RenderList`. DOM gives selectable, accessible text with native bidi. Canvas gives thousands of glyphs, per-letter effects, PNG/video export, and an accessible hidden-DOM mirror. A node picks its renderer, so both can be layered on one page. |

---

## 4. Architecture

```
Doc (JSON) ──► resolve (breakpoint, constraints, units) ──► behaviors.step(dt)
          ──► layout pass (pure) ──► RenderList ──► DOM renderer | Canvas renderer
                                                       ▲ diffed writes, paint-only fast path
```

Packages:
- **`@jitter/engine`**: framework-free TypeScript. It includes:
  - the font manager and prepare cache;
  - geometry (scanlines, regions, obstacles, offsets);
  - text flow and threading;
  - fit text, rich runs, ASCII and the effects;
  - `layoutScene(doc, env, t) → RenderList`.
- **`@jitter/render-dom`** and **`@jitter/render-canvas`**.
- **`@jitter/runtime`**: engine, renderers and behaviors. This is the shipped artifact, plus `web-component` and `react` wrappers.
- **`@jitter/editor`**: the app. React for the chrome only. The stage is engine-driven and outside React rendering.

### Key engine abstractions
- **Metric vs. paint attributes.** Font, size, weight, style, case, tracking and text change the
  metrics, so they trigger re-prepare. Color, decoration, opacity, image-fill and per-glyph transforms
  are paint-only, so they never re-prepare and never re-layout. This is the most important performance rule.
- **Shapes** are polygons with holes. Sources: rect, ellipse, path, glyph outline, image alpha,
  image threshold mask, and (later) ML segmentation. Shapes can be offset by padding using a real
  polygon offset (Clipper), not h/v padding.
- **Regions vs. obstacles.** A *region* is where text may go (a frame, the inside of the letter G).
  An *obstacle* is where it may not (an orb, a photo hull). For each line band: allowed intervals =
  region scanline intervals minus obstacle intervals, carved into slots.
  > The demo's `getPolygonIntervalForBand` merges to one `[minLeft, maxRight]` span, which **loses holes and concave gaps**.
  > Jitter needs true multi-interval scanlines (even-odd spans per sample row, intersected across the band).
- **Local coordinate frames.** Rotated frames (vertical "ettysburg") are laid out in local space,
  with obstacles transformed into it. The output is transformed back.
- **Story → Frames threading** through a cursor chain. **Overflow policy** per story: grow, clip,
  ellipsis, continue in the next frame, or shrink to fit.
- **Behaviors** (physics, spin, tween, hover/click triggers, per-letter animation) are separate from
  nodes, so new visual features plug in without touching layout.

---

## 5. Text and font system (modular, start small)

```ts
Story { paragraphs: Paragraph[] }            // source text, never case-transformed
Paragraph { runs: Run[], align, indent, spaceBefore/After, dropCap? }
Run { text, styleRef?, overrides: Partial<TextStyle> }
TextStyle {                                   // named & reusable, like Figma text styles
  // metric
  family, weight, italic, size, lineHeight, trackingEm, case: 'none'|'upper'|'lower'|'title'|'small-caps*'
  // paint
  color | gradient | imageFill, decoration, opacity, highlight/shape
}
FontStack = [primary, ...scriptFallbacks, emojiFont]
```

- **Fast path:** a paragraph with a single style uses `prepareWithSegments` and `layoutNextLine`.
  **Rich path:** mixed runs use `prepareRichInline` and `layoutNextRichInlineLineRange`, which also
  streams line by line, so it still flows around obstacles.
- **v1:** family and weight (Google Fonts), italic, size, line height, tracking, case,
  color, and bold/italic runs. **Later:** gradients and image fills, OpenType features,
  custom variable axes (canvas can't set arbitrary axes, so use named instances only), and true small caps.
- **Accents and Unicode:** Pretext is grapheme-correct. Our job is making sure the stack covers the
  glyphs (load Google subsets by sample text), and that `lang` is set.
- **Emoji:** always end the stack with an emoji font, and handle the DPR cache rule (§2 #11).

---

## 6. Combining images with text

| Feature (reference) | Technique | Builds on | Cost |
|---|---|---|---|
| **Text inside visual areas** (the Gettysburg "G") | The *region* shape is a glyph outline, a drawn path, or an image area. Text flows inside it using multi-interval scanlines. Rotated frames give vertical words. | Dynamic-layout band math, generalized | M |
| **Auto-suggested areas** in images | Tier 1: alpha channel (the demo's hull code) plus luminance/color threshold and connected components. Cheap, client-side, great for flat poster art. Tier 2: ML segmentation (SAM-class via ONNX/WebGPU, or a server API) for photos. | `wrap-geometry.ts` | Tier 1: S–M. Tier 2: L |
| **Text blocks with image wrap** (travel spread, microplastics) | Images are obstacles: a rect, or a hull from alpha. Per-image padding and offset shape. | Editorial and dynamic-layout demos | S (once the engine exists) |
| **Templated / uniform image-text distribution** (a "2D block editor") | Flow/stack/grid containers of flat rectangles. Images keep their aspect ratio. Text block heights come from `layout()` at a candidate width. A solver justifies rows (like justified galleries) or packs masonry. | `layout()`, masonry demo | M–L |
| **Images inside lines of text** ("36 ways…", "Your space isn't plain") | Rich-inline `{ width }` boxes for images between words, with per-line justification. | `rich-inline`, rich-note demo | M |
| **Text colored by an image** | Continuous: CSS `background-clip: text` on line elements, with the image background aligned to page coordinates (GPU, nearly free). Canvas: draw text, then composite the image `source-in`. Posterized per-word color: sample the image at each fragment's box. | Paint-only attribute | S–M |
| **Shape superposition** (calendar with shapes behind numbers) | Decorations painted behind or over fragments: pill, circle, blob or image, using fragment geometry from rich inline (`gapBefore`, `occupiedWidth`). Shapes can also be inline boxes that take space. | `rich-inline` | M |
| **Whitespace/negation from images** (text holes shaped like figures) | Layout mode: an image mask becomes an obstacle, and text routes around it. Paint mode (knockout): layout is unchanged and glyphs under the mask are hidden or faded. | Regions, obstacles, paint pass | M |
| **Curved text and per-letter animation** ("Wind Shape") | Text on a path: place each grapheme by arc length. Per-grapheme advances come from prefix measurement, to keep kerning. Multi-line text along offset curves. Rendering: canvas or SVG for large glyph counts, DOM spans under about 2k glyphs. Per-letter behaviors (stagger, physics, scatter). Latin/CJK only (§2 #8). | Engine plus behaviors | L |
| **Custom break shapes around images** (padding, shape, color, overlay) | Obstacle = shape + offset + optional visible "keep-out" fill/overlay painted beneath. | Shapes, Clipper offset | S–M |

---

## 7. Responsive layout

### The shape of the problem
In normal HTML, responsiveness mostly comes free: text reflows into whatever width it gets. Jitter
layouts are **print-style compositions** (absolute positions, shapes, text wrapping around them),
which have no natural answer for "what happens at 375px wide?". The problem has six dimensions:

1. **Geometry:** how each node's position and size resolve from the container (pin, stretch, scale, or percentage).
2. **Typography:** font size, line height and tracking at each size (fixed, fluid, or fit-to-box).
3. **Structure:** column count, threading order, stacking (a spread becomes a single column), and visibility.
4. **Content pressure:** shrinking frames make text overflow. Where does it go? This also decides whether **page height** is fixed (poster, like the demos) or content-driven (scrolling article).
5. **Media:** image crop and focal point, hull rescale (hulls are normalized, so this is cheap), and obstacle sizes relative to text.
6. **Embedding:** exported components live in arbitrary containers, so breakpoints must key off **container width**, not the window.

### Options

| Approach | How it works | Pros | Cons |
|---|---|---|---|
| **A. Scale-to-fit** | Fixed artboard, uniformly scaled like an SVG viewBox. | Trivial and pixel-identical. Wrapping is unchanged, so relayout can be skipped entirely and only a CSS transform applied. | Tiny text on phones. No real reflow. |
| **B. Breakpoint artboards with overrides** (Webflow/Framer) | Content is shared. Any layout property can be overridden per breakpoint, cascading desktop-first. | Full art direction. Matches designers' mental model and Figma's frame-per-size habit. | N× authoring effort. Jumps at boundaries. Overrides drift out of sync. |
| **C. Constraints** (Figma: pin left/right/center/stretch/scale, min/max) | Continuous resolution from the parent rect. | Works at every width. Low authoring cost. | Can't express structural change (3 cols→1). Free compositions overlap at extremes. |
| **D. Flow containers** (stack/grid/wrap, Auto Layout-like) | Children laid out by a solver. Pretext supplies exact text heights. | Truly responsive and robust. Natural for templated image/text distribution. | Less freeform. We build and maintain a layout solver. |
| **E. Expressions** (`clamp(18, 6cqw, 28)`, formulas like the demos use) | Any value can be a function of the environment. | Maximum power. Engineers love it. | Opaque to designers. Hard to edit visually. |
| **F. Constraint solver** (Cassowary) | Declarative relations between nodes. | Elegant. | Slow to debug, perf risk, and confusing in UI. Not recommended. |

### Recommendation: a hybrid of B, C and D, with E as an escape hatch
- **D** for structure: the page is a tree of containers. A container is *free* (absolute children)
  or *flow* (stack/grid). Flow containers can come after the MVP.
- **C** inside free containers: anchors plus percentage, container, or fluid units.
- **B** for art direction: breakpoints are **container-width** ranges. Each property is
  `base + sparse overrides`. The UI shows what is overridden and offers "reset to base".
- **E** as the value type: px, %, `cqw/cqh`, and `clamp(min, fluid, max)`. Designers see sliders,
  and engineers can type expressions.
- **A** as a page mode for posters and art pieces.
- Per page: a height mode (fixed / content / viewport). Per story: an overflow policy.

**v1 cut:** free containers, constraints, units, breakpoints with overrides for position, size,
visibility, font size, columns and obstacle scale, a scale-to-fit mode, and both height modes.
Flow containers follow in Phase 4.

---

## 8. Performance

**The budget:** about 16 ms per frame at 60 Hz (8 ms at 120 Hz), for **layout plus DOM commit plus
browser paint**, during drags and animations. That realistically leaves **about 4 ms for our layout
and about 4 ms for DOM writes**.

**Where the cost is:**
1. **`prepare()`.** It's slow: segmentation plus canvas measurement. It must never run per frame.
   It runs only on metric edits (text, font). Long stories are prepared per paragraph, so typing
   re-prepares only one paragraph.
2. **Geometry.** Bands × obstacles. A polygon interval costs O(rows in band × vertices). A
   3-column page has about 90 bands × 6 obstacles, which is fine for circles and rects but heavy for
   detailed hulls. Use simplified hulls, bounding-box rejection, and per-band caching for static obstacles.
3. **DOM commit.** Hundreds of positioned line nodes, each rewrite triggering style, layout and paint.
   Mitigate with the demos' diffing, `contain: strict`, and transforms instead of top/left.
   **Per-glyph effects multiply the node count 5–10×**, which DOM can't sustain.
4. **Pixel work.** `getImageData`, hull extraction, per-glyph image sampling and the ASCII palette.
   Precompute at import or edit time, cache by asset, use workers or idle callbacks, and ship
   precomputed results in exports.
5. **Editor overhead.** React re-rendering the inspector at 60 fps, and undo snapshots per frame.
   Keep the stage outside React, and coalesce a drag into one undo entry.

**Tradeoffs:**

| Choice | Option 1 | Option 2 | Recommendation |
|---|---|---|---|
| Renderer | DOM: accessible, selectable, bidi-correct, crisp, but node-count bound | Canvas/WebGL: thousands of glyphs, effects, export, but no native a11y/selection, and bidi issues | DOM default for text. Canvas for effect-heavy nodes, with a hidden semantic mirror. |
| Relayout scope | Full relayout every frame: simple | Incremental (dirty stories/bands only): scales, but complex | Story-level dirty flags first. Band-level only if profiling demands it. |
| Thread | Main thread: simple, no latency | Worker: no jank, but transfer latency and the emoji bug | Keep the engine pure so it *can* move. Start on the main thread. |
| Precision | Fine hulls and per-row sampling: accurate | Simplified hulls and coarse bands: fast | Per-shape quality setting. Coarse while dragging, refine on idle. |
| Precompute vs. runtime | Bake hulls and palettes into export: fast load, bigger payload | Compute at runtime: small payload, slower start | Bake by default. |

**Phase 0 sets a perf harness:** a reference scene (3 columns, 6 obstacles including 2 polygons,
a 2,000-word story) must lay out in under 4 ms and commit in under 4 ms on a mid-range laptop, and
in under 2× that on a mid-range phone. This gate is tracked in CI.

---

## 9. Priority demos as editor features (condensed)

- **Editorial engine:** frames with columns, story threading and overflow badges, a fit-text
  headline, drop cap, pull quotes as obstacles, circle/rect obstacles, a physics behavior
  (bounce, repel, click-to-pause), and edit vs. play modes.
- **Dynamic layout:** image nodes with alpha hulls (separate layout and hit-test hulls, with an
  overlay preview), polygon editing, rotation, spin/tween behaviors on click or hover, and
  obstacles crossing column boundaries.
- **Variable typographic ASCII:** an `AsciiField` node made of a grid, a **brightness source** and a palette.
  - Sources (pluggable): particles, fluid, image, video, webcam, or another node's render.
  - Palette controls: family, charset, weights, styles, error weights, invert, and color mapping.
  - The palette is built once per font configuration in idle time, then cached and baked into exports.

---

## 10. Phased plan (estimates assume one senior engineer; parallelizable phases noted)

| Phase | Scope | Est. |
|---|---|---|
| **0. Engine spike and perf harness** | Doc schema v0 with value/override types; engine for frames, threading, circle/rect/polygon obstacles with multi-interval scanlines, regions, and fit text; DOM renderer; the editorial demo rebuilt from JSON; perf gate. | 2–3 wk |
| **1. Editor MVP** | Stage (pan, zoom, select, transform, snap), layers, inspector, story panel with runs (bold, italic, color, case), Google Fonts picker and font manager, breakpoints with constraints and scale-to-fit, undo, local save (IndexedDB), and export as HTML, web component and React. | 7–9 wk |
| **2. Priority demos at parity** | Editorial (drop cap, pull quotes, physics, play mode), dynamic layout (image hulls, rotation, spin), and ASCII field with pluggable sources (canvas renderer v1 lands here). | 5–7 wk |
| **3. Accounts and cloud** *(parallel to 2)* | Supabase auth, projects, autosave, asset storage, font uploads. | 3–4 wk |
| **4. Images × text** | Text inside regions (glyph, path, threshold masks), auto-suggested areas tier 1, offset break shapes and keep-out styling, image-colored text, knockout, shape superposition, inline image boxes with justification, and flow containers with justified image/text distribution. | 6–8 wk |
| **5. Kinetic type** | Text on path, multi-line curves, per-letter behaviors, video/PNG export from the canvas renderer. | 4–6 wk |
| **Later** | ML segmentation, multiplayer (Yjs), Figma import, Jitter MCP/agent API, content binding/CMS, OpenType features, version history. | — |

---

## 11. Open questions

1. **Default height model for web exports:** viewport poster (like the demos) or scrolling article? Both will exist, but which is the default template?
2. **Content binding in v1?** Engineers will want to feed text and images through props. This is cheap if designed into the schema now (slot ids on stories and images).
3. **How high is Figma import on the list?** It shapes how closely our node model should mirror Figma frames and Auto Layout.
4. **Team size and timeline target.** The estimates above are for one engineer, and phases 2 and 3, then 4 and 5, parallelize well with two.

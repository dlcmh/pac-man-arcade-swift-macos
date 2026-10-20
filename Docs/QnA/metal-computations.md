# Is Metal used for all computations?

- **Project:** PAC-MAN — Metal Arcade
- **Recorded:** 2026-10-20 (+08:00, Asia/Kuala_Lumpur)
- **Last updated:** 2026-10-20

> New to Metal? The [Metal crash course](../METAL_CRASH_COURSE.md) builds every
> concept below from first principles, with web-development analogies and a
> line-by-line walkthrough of this project's renderer.

**No.** Metal is used only to draw the frame. Every gameplay computation —
movement, ghost decisions, collisions, scoring, timers, mode changes — runs in
plain Swift on the CPU. Audio is also CPU-generated, and windowing, input, and
persistence use AppKit and `UserDefaults` rather than Metal.

| Layer | Technology | What it does |
| --- | --- | --- |
| Simulation | Swift + Foundation, CPU | Game rules and state in `PacManCore` |
| Frame scheduling | AppKit / QuartzCore, CPU | `MTKView` callback and fixed-step accumulator |
| Geometry | Swift, CPU | Builds the frame's triangles in `Canvas` |
| Rasterisation | **Metal, GPU** | Transforms vertices, rasterises, blends, resolves MSAA |
| Audio | AVFoundation, CPU | Synthesises PCM buffers, then plays them |
| Input/persistence | AppKit + `UserDefaults` | Keyboard, window, high score, mute |

### Where the split happens

- [`Game.swift`](../../Sources/PacManCore/Game.swift) — `update` is the whole
  simulation update. `PacManCore` imports only `Foundation`; it has no Metal,
  AppKit, or audio imports.
- [`GameView.swift`](../../Sources/PacManArcade/GameView.swift) — `draw(in:)` runs
  a 60 Hz fixed-step loop on the CPU. Each step calls `game.update(dt:)` and
  processes events **before** asking the renderer to draw. The renderer receives
  an already-decided `PacManGame` and only reads it.
- [`Canvas.swift`](../../Sources/PacManArcade/Canvas.swift) — `Canvas` is the
  immediate-mode canvas that expands every wall, pellet, character, glyph, and
  scanline into triangles. This work is entirely on the CPU.
- [`Renderer.swift`](../../Sources/PacManArcade/Renderer.swift) — `render` does the
  CPU-side scene composition, buffer copy, and a single `drawPrimitives` type
  submission.
- [`MetalShaders.swift`](../../Sources/PacManArcade/MetalShaders.swift) —
  `MetalShaderSource` holds the entire GPU program: a vertex shader that scales
  the 2D position and converts it to clip space, and a fragment shader that
  returns the vertex colour. There is no lighting, simulation, or compute
  kernel here.
- [`SoundEngine.swift`](../../Sources/PacManArcade/SoundEngine.swift) — `makeBuffer`
  generates sound effects sample-by-sample into `AVAudioPCMBuffer`s with
  ordinary CPU code, then plays them through `AVAudioEngine`.

There are no Metal compute pipelines or compute command encoders in the
project; the only pipeline created is the render pipeline. The GPU does do
per-vertex and per-pixel work — transforming coordinates, rasterising triangles,
blending, and resolving 4× MSAA — but it never decides what the game does.

### Why it is split this way

The separation is an explicit architectural rule:
[`AGENTS.md`](../../AGENTS.md#non-negotiable-architecture). Keeping `PacManCore`
headless is what lets the checks executable import it with nothing but
Foundation — the imports at the top of
[`Checks/main.swift`](../../Checks/main.swift) are `PacManCore` plus `Foundation`
and nothing else — and run thousands of deterministic assertions on a machine
without needing a window or a drawable. It also keeps the simulation
reproducible: no frame timing, GPU scheduling, or rendering state can change a
ghost's decision.

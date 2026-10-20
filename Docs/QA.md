# Code Q&A

A running record of questions about how **PAC-MAN — Metal Arcade** works, with
answers grounded in the source. Each answer points at the exact files and lines
that implement the behavior. New entries are appended in the order asked.

## 1. How do the ghosts know how to hunt and move towards Pac-Man?

**Short answer:** they do not plan a route through the maze. Each ghost has a
*target point* that is recomputed from the current game state, and at every tile
center it greedily picks the walkable exit that moves it closest to that target.
Different targets for Blinky, Pinky, Inky, and Clyde produce the four distinct
"personalities"; scatter mode simply swaps the target for a fixed corner.

### The per-frame loop

The simulation runs as a fixed-step update. `updatePlaying` advances Pac-Man
first, then calls `updateGhosts`:

- [`Game.swift:312–340`](../Sources/PacManCore/Game.swift#L312-L340) — the
  playing-phase update, including the `updateGhosts(deltaTime)` call at line 333.

Each ghost is a small state machine — `house`, `leaving`, `roam`, or `eyes`:

- [`Game.swift:459–490`](../Sources/PacManCore/Game.swift#L459-L490) — the
  per-ghost switch. Only `roam` (normal hunting) and `eyes` (returning home) use
  the shared movement routine `advanceGhost`; `house` bobs in place and
  `leaving` follows a scripted exit through the door.

### Movement is tile-to-tile

Ghosts move along tile centers, just like Pac-Man. When a ghost reaches a tile
center, `advanceGhost` decides where it may go next:

- [`Game.swift:515–567`](../Sources/PacManCore/Game.swift#L515-L567) — speed
  selection, tunnel slowdown, and the decision point at `isAtTileCenter`.

At that center it:

1. Wraps through the tunnel if needed and converts the position to a
   `GridPoint`.
2. Collects the neighboring directions whose tiles are walkable (the ghost door
   is only allowed for `eyes`).
3. Removes the reverse of the current direction, unless that is the only option
   (a dead end). This is the arcade rule that ghosts cannot turn around in a
   corridor:
   [`Game.swift:552–560`](../Sources/PacManCore/Game.swift#L552-L560).
4. Asks `chooseGhostDirection` to pick one of the remaining options, then keeps
   travelling in that direction until the next tile center.

### The greedy choice

- [`Game.swift:593–628`](../Sources/PacManCore/Game.swift#L593-L628) —
  `chooseGhostDirection`.

For a normal (non-frightened, non-eyes) ghost it calls `ghostTarget(for:)`, then
scores each available option by the **squared straight-line distance** from the
neighboring tile's center to the target, and keeps the smallest:

```swift
let target = ghostTarget(for: ghost.kind)
for direction in options {
    let neighbor = maze.neighbor(of: tile, in: direction)
    let distance = neighbor.squaredDistance(to: target)
    if distance < bestDistance { ... }
}
```

Because `available` is built from `Direction.decisionOrder` — up, left, down,
right — equally good choices are resolved in that arcade order (strict `<`
keeps the first):
[`Math.swift:118–119`](../Sources/PacManCore/Math.swift#L118-L119).

This is a *local* heuristic, not a shortest-path search. A ghost can be led
away from Pac-Man by a locally closer turn; the hunting behavior emerges from
re-evaluating the target at every tile center.

### The four targets

- [`Game.swift:630–663`](../Sources/PacManCore/Game.swift#L630-L663) —
  `ghostTarget(for:)`.

| Ghost | Chase target | Scatter corner |
| --- | --- | --- |
| **Blinky** | Pac-Man's current position. | `(26, -3)`, top right |
| **Pinky** | Four tiles ahead of Pac-Man; when Pac-Man faces up, `x` is also shifted 4 left to preserve the original game's overflow quirk. | `(1, -3)`, top left |
| **Inky** | Take the tile two ahead of Pac-Man, double the vector from Blinky to it: `2 * pivot - blinky`. | `(27, 32)`, bottom right |
| **Clyde** | Pac-Man when farther than 8 tiles; otherwise his scatter corner. | `(0, 32)`, bottom left |

Targets may lie outside the maze (the scatter corners do), which is fine — they
are only used for distance comparisons; the ghost still has to obey walls.

### Scatter, chase, and frightened

- [`Game.swift:165–174`](../Sources/PacManCore/Game.swift#L165-L174) — the
  scatter/chase schedule (7s scatter, 20s chase, … ending in permanent chase).
- [`Game.swift:669–682`](../Sources/PacManCore/Game.swift#L669-L682) —
  `updateGhostMode` advances the schedule and flips `ghostMode`, which is what
  `ghostTarget` checks first. Every mode change forces roaming ghosts to
  reverse (`forceReverse`), handled at
  [`Game.swift:478–483`](../Sources/PacManCore/Game.swift#L478-L483).
- While a power pellet is active the mode timer is paused, and the decision
  code ignores targets entirely: frightened ghosts pick a uniformly random
  available direction:
  [`Game.swift:612–614`](../Sources/PacManCore/Game.swift#L612-L614). The random
  source is the deterministic `SplitMix64` in
  [`Math.swift:126–150`](../Sources/PacManCore/Math.swift#L126-L150), so runs
  remain reproducible.

### Eyes use real pathfinding

Eaten ghosts are the exception: they navigate home with a precomputed
breadth-first distance field rather than the greedy target heuristic. The field
is built once by `Maze` from the ghost-house return tile `(13, 14)` and wraps
through both tunnels:
[`Maze.swift:147–179`](../Sources/PacManCore/Maze.swift#L147-L179). The eyes
state then picks the neighbor with the smallest house distance
([`Game.swift:598–610`](../Sources/PacManCore/Game.swift#L598-L610)), and on
reaching the return tile it re-enters the house
([`Game.swift:542–550`](../Sources/PacManCore/Game.swift#L542-L550)).

### Exit and speed

- Ghosts start in the house with staggered release delays and leave through a
  scripted path to the door and up to row 11.5:
  [`Game.swift:492–513`](../Sources/PacManCore/Game.swift#L492-L513) and
  [`Game.swift:825–864`](../Sources/PacManCore/Game.swift#L825-L864).
- Base ghost speed scales with level; frightened ghosts move at 61% speed, eyes
  at 13 tiles/second, and all of them slow to 55% in the tunnels:
  [`Game.swift:515–529`](../Sources/PacManCore/Game.swift#L515-L529).

### In one sentence

Each ghost repeatedly asks "which legal turn puts my tile center closest to my
personal target point?", and the four personalities differ only in how that
target is computed — a direct chase, a lookahead point, a mirrored vector off
Blinky, or a distance-triggered corner retreat.

## 2. What is BFS?

**BFS** stands for **breadth-first search**. It is a way of exploring a graph —
here, the maze's tiles — by expanding outward one "ring" of neighbours at a
time. A queue holds the tiles still to visit: take the oldest tile off the
front, look at every tile one step away from it, and add the ones that have not
been seen yet to the back.

The important property is that, in a graph where every move has the same cost,
BFS discovers each tile by a **shortest path**. It reaches all tiles one step
from the start first, then all tiles two steps away, and so on. A tile is never
given a longer distance after a shorter one, because the shorter route is
always found first.

### How this game uses it

The arcade uses BFS once, when the maze is created, to build a lookup table of
every tile's distance to the ghost house:

- [`Maze.swift:153–179`](../Sources/PacManCore/Maze.swift#L153-L179) —
  `computeHouseDistances` seeds the queue with the return tile `(13, 14)` at
  distance 0. It then pops a tile, tests its four neighbours, skips walls and
  out-of-bounds tiles, wraps tunnel columns, and enqueues each unvisited tile
  with `distance + 1`.
- [`Maze.swift:69–72`](../Sources/PacManCore/Maze.swift#L69-L72) and
  [`Maze.swift:147–151`](../Sources/PacManCore/Maze.swift#L147-L151) — the
  result is stored as the flat `houseDistance` array, indexed by
  `row * columns + column`.
- [`Game.swift:598–610`](../Sources/PacManCore/Game.swift#L598-L610) — a ghost
  in the `eyes` state simply compares the stored distances of its legal
  neighbours and moves to the smallest one. It is always walking downhill, so
  no search happens during play.

The BFS treats the ghost door as walkable (it only rejects walls), which is why
eaten ghosts can pass back into the house. Because the maze is small — 28 × 31
tiles — the whole table costs O(rows × columns) and is built once at startup.

### Why not use BFS for chasing?

The normal ghosts deliberately do not pathfind. They use the much cheaper
greedy target rule described in question 1, evaluating only the immediate exits
at each tile center. That is the authentic arcade behavior: ghosts can be
baited into taking a locally shorter turn that leads away from Pac-Man. BFS
would make them perfect pursuers and lose that character.

## 3. Is Metal used for all computations?

> New to Metal? The [Metal crash course](METAL_CRASH_COURSE.md) builds every
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

- [`Game.swift:280–310`](../Sources/PacManCore/Game.swift#L280-L310) — the whole
  simulation update. `PacManCore` imports only `Foundation`; it has no Metal,
  AppKit, or audio imports.
- [`GameView.swift:90–111`](../Sources/PacManArcade/GameView.swift#L90-L111) —
  the `MTKView` draw callback runs a 60 Hz fixed-step loop on the CPU. Each step
  calls `game.update(dt:)` and processes events **before** asking the renderer
  to draw. The renderer receives an already-decided `PacManGame` and only reads
  it.
- [`Canvas.swift:36–73`](../Sources/PacManArcade/Canvas.swift#L36-L73) — the
  immediate-mode canvas expands every wall, pellet, character, glyph, and
  scanline into triangles. This work is entirely on the CPU.
- [`Renderer.swift:78–148`](../Sources/PacManArcade/Renderer.swift#L78-L148) —
  the CPU-side scene composition, buffer copy, and a single
  `drawPrimitives(type: .triangle, ...)` submission.
- [`MetalShaders.swift:24–40`](../Sources/PacManArcade/MetalShaders.swift#L24-L40)
  — the entire GPU program: a vertex shader that scales the 2D position and
  converts it to clip space, and a fragment shader that returns the vertex
  colour. There is no lighting, simulation, or compute kernel here.
- [`SoundEngine.swift:190–207`](../Sources/PacManArcade/SoundEngine.swift#L190-L207)
  — sound effects are generated sample-by-sample into `AVAudioPCMBuffer`s by
  ordinary CPU code, then played through `AVAudioEngine`.

There are no Metal compute pipelines or compute command encoders in the
project; the only pipeline created is the render pipeline. The GPU does do
per-vertex and per-pixel work — transforming coordinates, rasterising triangles,
blending, and resolving 4× MSAA — but it never decides what the game does.

### Why it is split this way

The separation is an explicit architectural rule:
[`AGENTS.md:66–70`](../AGENTS.md#L66-L70). Keeping `PacManCore` headless is what
lets the checks executable import it with nothing but Foundation
([`Checks/main.swift:1–2`](../Checks/main.swift#L1-L2)) and run thousands of
deterministic assertions on a machine without needing a window or a drawable.
It also keeps the simulation reproducible: no frame timing, GPU scheduling, or
rendering state can change a ghost's decision.

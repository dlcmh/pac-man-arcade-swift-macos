# How do the ghosts know how to hunt and move towards Pac-Man?

- **Project:** PAC-MAN — Metal Arcade
- **Recorded:** 2026-10-20 (+08:00, Asia/Kuala_Lumpur)
- **Last updated:** 2026-10-20

**Short answer:** they do not plan a route through the maze. Each ghost has a
*target point* that is recomputed from the current game state, and at every tile
center it greedily picks the walkable exit that moves it closest to that target.
Different targets for Blinky, Pinky, Inky, and Clyde produce the four distinct
"personalities"; scatter mode simply swaps the target for a fixed corner.

### The per-frame loop

The simulation runs as a fixed-step update. `updatePlaying` advances Pac-Man
first, then calls `updateGhosts`:

- [`Game.swift`](../../Sources/PacManCore/Game.swift) — `updatePlaying` is the
  playing-phase update; the `updateGhosts(deltaTime)` call comes after Pac-Man
  has moved.

Each ghost is a small state machine — `house`, `leaving`, `roam`, or `eyes`:

- [`Game.swift`](../../Sources/PacManCore/Game.swift) — `updateGhost` holds the
  per-ghost switch. Only `roam` (normal hunting) and `eyes` (returning home) use
  the shared movement routine `advanceGhost`; `house` bobs in place and
  `leaving` follows a scripted exit through the door.

### Movement is tile-to-tile

Ghosts move along tile centers, just like Pac-Man. When a ghost reaches a tile
center, `advanceGhost` decides where it may go next:

- [`Game.swift`](../../Sources/PacManCore/Game.swift) — `advanceGhost` selects speed
  (including tunnel slowdown) and takes the decision branch at `isAtTileCenter`.

At that center it:

1. Wraps through the tunnel if needed and converts the position to a
   `GridPoint`.
2. Collects the neighboring directions whose tiles are walkable (the ghost door
   is only allowed for `eyes`).
3. Removes the reverse of the current direction, unless that is the only option
   (a dead end). This is the arcade rule that ghosts cannot turn around in a
   corridor: the `available` filter in `advanceGhost` drops
   `ghost.direction.opposite` when another choice exists.
4. Asks `chooseGhostDirection` to pick one of the remaining options, then keeps
   travelling in that direction until the next tile center.

### The greedy choice

- [`Game.swift`](../../Sources/PacManCore/Game.swift) — `chooseGhostDirection`.

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

- [`Math.swift`](../../Sources/PacManCore/Math.swift) — `decisionOrder` is the
  fixed tie-break order.

This is a *local* heuristic, not a shortest-path search. A ghost can be led
away from Pac-Man by a locally closer turn; the hunting behavior emerges from
re-evaluating the target at every tile center.

### The four targets

- [`Game.swift`](../../Sources/PacManCore/Game.swift) — `ghostTarget(for:)`.

| Ghost | Chase target | Scatter corner |
| --- | --- | --- |
| **Blinky** | Pac-Man's current position. | `(26, -3)`, top right |
| **Pinky** | Four tiles ahead of Pac-Man; when Pac-Man faces up, `x` is also shifted 4 left to preserve the original game's overflow quirk. | `(1, -3)`, top left |
| **Inky** | Take the tile two ahead of Pac-Man, double the vector from Blinky to it: `2 * pivot - blinky`. | `(27, 32)`, bottom right |
| **Clyde** | Pac-Man when farther than 8 tiles; otherwise his scatter corner. | `(0, 32)`, bottom left |

Targets may lie outside the maze (the scatter corners do), which is fine — they
are only used for distance comparisons; the ghost still has to obey walls.

### Scatter, chase, and frightened

- [`Game.swift`](../../Sources/PacManCore/Game.swift) — `modeSchedule` defines the
  scatter/chase schedule: 7s scatter, 20s chase, … ending in permanent chase.
- [`Game.swift`](../../Sources/PacManCore/Game.swift) — `updateGhostMode` advances
  the schedule and flips `ghostMode`, which is what `ghostTarget` checks first.
  Every mode change forces roaming ghosts to reverse: `forceReverse` is the flag
  that `updateGhost` acts on.
- While a power pellet is active the mode timer is paused, and the decision
  code ignores targets entirely: with `frightenedRemaining` above zero,
  `chooseGhostDirection` picks a uniformly random available direction. The
  random source is [`Math.swift`](../../Sources/PacManCore/Math.swift) —
  `SplitMix64` — so runs remain reproducible.

### Eyes use real pathfinding

Eaten ghosts are the exception: they navigate home with a precomputed
[breadth-first](breadth-first-search.md) distance field rather than the greedy
target heuristic. The field
is built once by `Maze` from the ghost-house return tile `(13, 14)` and wraps
through both tunnels:

- [`Maze.swift`](../../Sources/PacManCore/Maze.swift) — `computeHouseDistances`
  seeds the BFS and fills the field.

The eyes state then picks the neighbor with the smallest house distance, which
is the `eyes` branch of `chooseGhostDirection` in
[`Game.swift`](../../Sources/PacManCore/Game.swift) — `houseDistance`. On reaching
`ghostHouseReturnTile` it re-enters the house; that hand-off lives in
[`Game.swift`](../../Sources/PacManCore/Game.swift) — `advanceGhost`.

### Exit and speed

- Ghosts start in the house with staggered release delays and leave through a
  scripted path to the door and up to row 11.5:
  [`Game.swift`](../../Sources/PacManCore/Game.swift) — `releaseDelay` counts down
  in `updateGhost`, and the per-level `releaseScale` multiplier spaces the
  ghosts out.
- Base ghost speed scales with level; frightened ghosts move at 61% speed, eyes
  at 13 tiles/second, and all of them slow to 55% in the tunnels.
  [`Game.swift`](../../Sources/PacManCore/Game.swift) — `ghostSpeed` sets the base
  speed and `advanceGhost` applies the frightened and tunnel multipliers.

### In one sentence

Each ghost repeatedly asks "which legal turn puts my tile center closest to my
personal target point?", and the four personalities differ only in how that
target is computed — a direct chase, a lookahead point, a mirrored vector off
Blinky, or a distance-triggered corner retreat.

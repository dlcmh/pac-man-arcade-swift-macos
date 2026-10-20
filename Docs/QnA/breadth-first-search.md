# What is BFS?

- **Project:** PAC-MAN — Metal Arcade
- **Recorded:** 2026-10-20 (+08:00, Asia/Kuala_Lumpur)
- **Last updated:** 2026-10-20

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

- [`Maze.swift`](../../Sources/PacManCore/Maze.swift) — `computeHouseDistances`
  seeds the queue with the return tile `(13, 14)` at distance 0. It then pops a
  tile, tests its four neighbours, skips walls and out-of-bounds tiles, wraps
  tunnel columns, and enqueues each unvisited tile with `distance + 1`.
- [`Maze.swift`](../../Sources/PacManCore/Maze.swift) — the result is stored as the
  flat `houseDistance` array, indexed by `row * columns + column`.
- [`Game.swift`](../../Sources/PacManCore/Game.swift) — a ghost in the `eyes` state
  simply compares the stored distances of its legal neighbours
  (`maze.houseDistance`) and moves to the smallest one. It is always walking
  downhill, so no search happens during play.

The BFS treats the ghost door as walkable (it only rejects walls), which is why
eaten ghosts can pass back into the house. Because the maze is small — 28 × 31
tiles — the whole table costs O(rows × columns) and is built once at startup.

### Why not use BFS for chasing?

The normal ghosts deliberately do not pathfind. They use the much cheaper
greedy target rule described in
[question 1](ghost-hunting-and-movement.md), evaluating only the immediate exits
at each tile center. That is the authentic arcade behavior: ghosts can be
baited into taking a locally shorter turn that leads away from Pac-Man. BFS
would make them perfect pursuers and lose that character.

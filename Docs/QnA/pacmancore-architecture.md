# How does PacManCore work, and what software-engineering principles does it demonstrate?

- **Project:** PAC-MAN — Metal Arcade
- **Recorded:** 2026-10-20 (+08:00, Asia/Kuala_Lumpur)
- **Last updated:** 2026-10-20

**Short answer:** `PacManCore` is not a helper library that the app calls for a
few rules. It *is* the game. It owns the maze, the actors, the state machine,
the scoring, and the clock, and it can run the entire simulation with no window,
no GPU, no keyboard, and no speakers. The macOS app is a thin adapter that feeds
it input, advances it on a timer, reads its state for drawing, and translates its
events into sound. That inversion is what makes the rules testable and keeps them
from being reimplemented in the renderer.

## What is inside the core

| File | Responsibility |
| --- | --- |
| [`Maze.swift`](../../Sources/PacManCore/Maze.swift) — `Maze` | The canonical 28 × 31 board, tile walkability, tunnel wrapping, pellets, and the precomputed ghost-house distance field |
| [`Game.swift`](../../Sources/PacManCore/Game.swift) — `PacManGame` | The phase state machine, commands, movement, ghost AI, collisions, scoring, fruit, and events |
| [`Math.swift`](../../Sources/PacManCore/Math.swift) — `Vec2` | The position and grid value types, `Direction`, and the seeded `SplitMix64` random generator |

Only `Foundation` is imported. There is no AppKit, Metal, MetalKit, or
AVFoundation anywhere in the target. The package makes the dependency direction
explicit: both `PacManArcade` and `PacManChecks` depend on the core, and the core
depends on neither of them:

- [`Package.swift`](../../Package.swift) — `PacManCore` is a standalone library
  target; the executable target links AppKit, Metal, and AVFoundation, but those
  frameworks are not visible to the core.

## One tick, from command to consequence

The public surface is deliberately small. A caller can start a game, send a
direction, pause, advance time, and drain events. Everything else is
read-only state:

```swift
game.requestStart()
game.setDirection(.left)
game.update(dt: 1.0 / 60.0)
let events = game.drainEvents()
```

1. **Construction.** `PacManGame.init` creates a `Maze`, loads the pellets, and
   calls `resetActors` to place Pac-Man and the four ghosts. The high score is
   passed in rather than read from `UserDefaults`, so storage stays outside the
   core.
2. **Commands are intentions, not teleports.** `setDirection` only records a
   buffered desired direction on Pac-Man; `movePac` decides whether the next
   tile allows it. `requestStart` transitions from attract or game over to the
   ready phase. The app cannot move an actor directly.
3. **`update(dt:)` is the only clock.** It clamps abnormal deltas, advances the
   simulated `elapsed` time, updates popups, and switches on the phase. In
   `.playing`, `updatePlaying` runs the rules in a fixed order: timers, fruit,
   direction buffer, Pac-Man movement, ghost movement, fruit pickup, ghost
   collision, and level completion.
4. **State and events are the outputs.** The app reads `public private(set)`
   properties for rendering. Gameplay consequences that the app might want to
   hear — a chomp, a power pellet, a ghost eaten, a death — are queued as
   `GameEvent` values and collected with `drainEvents`. The core never calls
   `AVAudioEngine` or a renderer.
5. **The checks drive the same interface.** [`Checks/main.swift`](../../Checks/main.swift)
   imports only `Foundation` and `PacManCore`, creates a `PacManGame`, and calls
   `update(dt:)` in fixed steps. Its `check` helper asserts against the same
   public API the app uses. No test-only back doors are needed.

## What the app layer actually does

- [`GameView.swift`](../../Sources/PacManArcade/GameView.swift) — `draw(in:)`
  owns the wall clock and the fixed-step accumulator. It calls `update` at 60 Hz,
  translates key presses into `setDirection` or `requestStart`, drains events for
  sound, and persists the high score.
- [`Renderer.swift`](../../Sources/PacManArcade/Renderer.swift) — `render` reads
  the finished `PacManGame` state and builds triangles. It never writes gameplay
  state; it does not know the ghost targeting rules.
- [`SoundEngine.swift`](../../Sources/PacManArcade/SoundEngine.swift) — `play`
  turns a `GameEvent` into a synthesized sound. The core has no audio concepts.
- [`.md` documentation policy](../../AGENTS.md#documentation-and-code-references) —
  the architectural rule that `PacManGame` is authoritative and the renderer is
  read-only is stated in the repository instructions, not just implied by the
  code.

## The software-engineering principles

### 1. Separation of concerns

The core answers "what happens in the game?" The shell answers "how does this
platform show, hear, and schedule it?" Rendering, input, audio, and storage can
change without touching the rules. That is why the Metal renderer can be
replaced, or a test harness can replace it entirely, without reimplementing
ghost movement.

### 2. Ports and adapters (hexagonal architecture)

The core sits in the centre. Its *ports* are the command methods
(`requestStart`, `setDirection`, `togglePause`, `update`), the read-only state
properties, and the `drainEvents` output. The *adapters* are AppKit input, the
Metal renderer, AVAudioEngine, and `UserDefaults`. Adapters depend on the core;
the core knows nothing about them. That is the dependency-inversion rule in
practice: source-code dependencies point inward.

### 3. A deterministic state-machine core with an imperative shell

The update is a state machine over `GamePhase` and the actor states. The shell
supplies real time; the core consumes fixed-size deltas. The `SplitMix64` RNG is
seeded and lives in the core, so frightened-ghost choices are reproducible.
There is no `Date()`, no system randomness, and no frame-rate-dependent
movement inside the simulation. The core is not a *pure* functional core — it
mutates its own state — but it is a deterministic core with all I/O pushed to
the shell, which is the useful half of the functional-core/imperative-shell
pattern.

### 4. Single source of truth

There is exactly one implementation of the maze, collision radius, ghost
targeting, scoring, and phase transitions. The renderer draws what the core
says; it does not decide that a ghost was eaten. This is the DRY principle
applied at the architectural level: duplicate the rules and they will drift,
especially when a second platform or a second renderer appears.

### 5. Encapsulation and information hiding

`PacManGame` exposes `public private(set)` state and explicit commands. Callers
can observe `score`, `phase`, `ghosts`, and `pellets`, but cannot assign them.
The internal timers, mode stage, combo counter, and RNG stay private. That keeps
the invariants inside the type that owns them and gives the shell a narrow,
stable contract.

### 6. Testability as an architectural constraint

Because the core has no UI dependency, `PacManChecks` is an ordinary executable
that runs thousands of deterministic assertions in milliseconds. It can simulate
a 60-second soak, an autopilot run, a death, and a game over without a window or
a Metal device. Testability is not an afterthought here; the dependency rule was
chosen partly to make it possible.

### 7. High cohesion, low coupling

`Maze` owns geometry and navigation; `PacManGame` owns rules and time;
`Math.swift` owns small value types and the RNG. Each file has one reason to
change. The coupling that remains is intentional: the game needs the maze, and
the app needs the game's public API.

## The "native-agnostic core" insight

The chat insight is right about the risk: if six native shells each own their own
ghost AI and scoring, six subtly different games appear, and every bug fix has to
be made six times. This repository answers the risk with one authoritative
implementation in Swift and two very different consumers: the Metal app and the
headless checks.

The language question is secondary to the boundary question. A core is portable
when its dependencies are portable. Here the core depends on Swift and
`Foundation`, not on AppKit or Metal, so it could be reused by another Swift
shell without changes. The package currently declares macOS 13 only, and no
other platform is configured or tested in this repository; "portable in
principle" is not the same as "shipped on six platforms."

If a future shell cannot host Swift, the realistic options are a stable C ABI or
FFI boundary around the one core, or a port of the core to that platform's
language. Either way, the thing that prevents drift is not the language alone:
it is a shared conformance suite. `PacManChecks` is that suite in miniature. One
core plus one behavioural specification, with many thin shells, scales far better
than six independent rule engines.

## What the design costs

This is not free architecture. The boundary adds indirection: the app must drain
events, pass fixed deltas, and avoid reaching into state. The core cannot use GPU
acceleration or platform-specific storage even if that would be convenient. It
is single-threaded and object-oriented rather than data-oriented, which is fine
for a game of this size but would not scale unchanged to a large simulation. The
payoff is a rule set that can be reasoned about, tested, and reused independently
of the platform — which is exactly the property the insight is asking for.

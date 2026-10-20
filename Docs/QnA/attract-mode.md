# What is attract mode?

- **Project:** PAC-MAN — Metal Arcade
- **Recorded:** 2026-10-20 (+08:00, Asia/Kuala_Lumpur)
- **Last updated:** 2026-10-20

**Attract mode** is the idle presentation shown when the machine is waiting for
a player. The name comes from the arcade business: the screen exists to *attract*
someone walking past into inserting a coin. In this game it is the title screen
with the maze, the ghost lineup, the controls, and the pulsing **PRESS ENTER TO
PLAY** prompt. See [`title-screen.png`](../title-screen.png) for the rendered result.

This implementation's attract mode is **not** a self-playing demo. The original
arcade ran scripted AI games behind the title; here the board is static and only
the title-panel animations move.

### The state

- [`Game.swift`](../../Sources/PacManCore/Game.swift) — `GamePhase` declares the
  `.attract` case, and `phase` starts there when `PacManGame` is created. It is
  the only phase in which no game has begun.
- [`Game.swift`](../../Sources/PacManCore/Game.swift) — `update(dt:)` deliberately
  breaks out for `.attract` and `.gameOver` after advancing `elapsed` and the
  score popups. Pac-Man, the ghosts, pellets, and timers are all frozen, but the
  clock keeps running so the title animations can pulse.
- [`Game.swift`](../../Sources/PacManCore/Game.swift) — `requestStart` accepts input
  only in `.attract` or `.gameOver`, then calls `startNewGame`, which resets the
  board and moves to `.ready` for the familiar "READY!" pause.

Attract mode is therefore distinct from game over: after a loss the phase stays
`.gameOver` and `drawGameOverOverlay` is shown, not the title panel. The initial
launch and a finished game merely share the same legal way to begin.

### Saying yes to the coin

- [`GameView.swift`](../../Sources/PacManArcade/GameView.swift) — `keyDown` treats
  Return, Space, and keypad Enter as "start" when the phase is `.attract` or
  `.gameOver`, forwarding to `requestStart`. The `PACMAN_AUTOSTART` environment
  variable bypasses the wait for screenshots and quick launches.
- [`Renderer.swift`](../../Sources/PacManArcade/Renderer.swift) — `drawOverlays`
  switches on the phase and calls `drawAttractOverlay` for `.attract`, so the
  renderer only chooses which completed state to present.
- [`Renderer.swift`](../../Sources/PacManArcade/Renderer.swift) —
  `drawAttractOverlay` dims the playfield, draws the framed **PAC-MAN** title,
  the four named ghosts, a chomping Pac-Man mascot, the control hints,
  `1 CREDIT`, the persisted best score, and the pulsing start prompt. Its
  animation phases are driven by the still-advancing `elapsed` value.

The ordinary HUD is drawn underneath the overlay, which is why the high score
and level information remain visible on the title screen.

# AGENTS.md

Operating instructions for AI coding agents working in this repository. These
rules are mandatory unless the maintainer gives a direct instruction that
supersedes them. Update this file when project policy changes.

- **Project:** PAC-MAN — Metal Arcade
- **Canonical repository:** <https://github.com/dlcmh/pac-man-arcade-swift-macos>
- **Maintainer:** [@dlcmh](https://github.com/dlcmh)
- **Governance baseline:** 2026-10-20
- **Current release:** 1.0

## Read first

1. [Docs/PROJECT_ORIGIN.md](Docs/PROJECT_ORIGIN.md) — why this project exists,
   including the original request. Its quoted request is a historical record
   and must not be edited.
2. [GOVERNANCE.md](GOVERNANCE.md) — decision-making, releases, licensing, and
   amendment rules.
3. [CONTRIBUTING.md](CONTRIBUTING.md) — build, test, and contribution workflow.
4. [SECURITY.md](SECURITY.md) — vulnerability reporting and privacy posture.

## Project layout

| Path | Responsibility |
| --- | --- |
| `Sources/PacManCore/` | Pure Swift simulation. Foundation only; no AppKit, Metal, or audio imports. |
| `Sources/PacManArcade/` | macOS app, Metal renderer, input, procedural audio, and persistence. |
| `Checks/` | Dependency-free simulation checks executable. |
| `Resources/` | App metadata and generated icon files. |
| `Docs/` | Screenshots, project origin, code Q&A, Metal crash course, and Refactoring decision records under `Docs/Refactoring/`. |
| `scripts/` | Deterministic app-bundle packaging, icon generation, and documentation link checking. |
| `dist/` | Generated, git-ignored app and DMG artifacts. Never commit it. |

## Prerequisites

- macOS 13 or newer on a Metal-capable Mac.
- A Swift toolchain from Xcode or the Apple Command Line Tools.
- No third-party runtime dependencies, package managers, or network services.

The bootstrap environment used only the Command Line Tools and did not include
XCTest. This is why verification lives in the standalone `PacManChecks`
executable instead of an XCTest target. Do not replace it with XCTest unless
you verify the toolchain first.

## Build, run, and verify

Run these from the repository root:

```bash
swift build                         # compile debug
swift run PacManArcade              # launch the game
swift run PacManChecks              # run the simulation checks
make app                            # build the release app bundle
make dmg                            # build dist/PAC-MAN-1.0.dmg
make checks                         # alias for the checks executable
make docs-check                     # validate doc links and code references
```

`swift build` is necessary but not sufficient for rendering changes. The Metal
shader is compiled at runtime, so a successful build can still launch into an
error alert if the MSL is invalid. After touching shaders, renderer code,
windowing, input, or audio, launch the app and confirm it actually runs.

## Non-negotiable architecture

1. **Keep simulation and presentation separate.** `PacManCore` must remain
   headless and UI-framework-free so it can be exercised by `PacManChecks` and
   future tools. Do not import AppKit, Metal, MetalKit, or AVFoundation there.
2. **Keep Metal.** Use the existing single-pass, immediate-mode triangle
   renderer and `MTKView`. Do not replace it with SpriteKit, SceneKit, Core
   Animation, or an external game engine.
3. **Keep assets procedural.** Maze art, characters, fruit, logo, font, icon,
   and audio are generated in code. Do not add ripped arcade sprites, ROM data,
   scans, or copyrighted audio.
4. **Keep the game offline.** No network calls, telemetry, analytics, remote
   configuration, or account systems. The only persisted state is local
   `UserDefaults`.
5. **No new dependencies** without explicit maintainer approval.
6. **Authoritative simulation is `PacManGame`.** Do not duplicate gameplay
   rules in the renderer or app layer. Renderer state must be read-only.
7. **Keep the game loop deterministic and fixed-step.** The app currently runs
   simulation updates at 60 Hz with a bounded catch-up loop. Avoid frame-rate-
   dependent movement, timers, or random behavior.
8. **Preserve public read-only state.** Prefer `public private(set)` and
   explicit commands over mutable public fields. Tests should drive the public
   input API rather than test-only back doors.

## Gameplay invariants

Changes that affect the maze, movement, or ghost behavior must preserve or
deliberately update these known invariants and their checks:

- The maze is 28 × 31 with 240 dots and 4 power pellets (244 pellets total).
- Every pellet is reachable from the Pac-Man start.
- Both tunnel mouths wrap horizontally on row 14.
- Ghost eyes can route back into the ghost house through its door.
- Pac-Man turns only at tile centers via buffered input; reversal is immediate.
- Blinky, Pinky, Inky, and Clyde retain their distinct arcade targeting rules.
- Scatter/chase switching, frightened mode, ghost-house release, eaten-ghost
  eyes, and death/reset behavior continue to work.
- The README documents controls and deliverables accurately.

The level-256 kill screen from the historical arcade machine is acknowledged in
the origin record but is not emulated in v1.0. Do not add it as a drive-by
change; scope it with the maintainer first.

## Testing standard

`Checks/main.swift` is the regression suite. Add checks when changing gameplay,
movement, collision, scoring, or state transitions. The suite intentionally uses
only public game APIs.

A green run currently ends with:

```text
PASS: 21637 checks
PASS: 21646 checks (including power-pellet autopilot, ghost collision, and game over)
```

Counts may grow. The important requirement is that all checks pass. For pure
visual or packaging changes, also rebuild and open the resulting `.app`.

## Documentation and code references

A line number in prose is wrong the moment ten lines are inserted above it, and
nothing fails. Documentation therefore cites a **file and a symbol**, never a
line range:

```markdown
[`Game.swift`](Sources/PacManCore/Game.swift) — `updatePlaying`
```

- Link the file, then name the symbol in backticks on the same line or in the
  same sentence.
- Prefer the most specific symbol — a function, property, or type — over a
  general word such as a state name.
- Link Markdown by heading anchor
  (`../AGENTS.md#non-negotiable-architecture`), never by line.
- When a symbol is renamed or removed, update every document that cites it.

`make docs-check` enforces this: every relative link must resolve, every heading
anchor must exist, every cited symbol must still occur in the linked file, and
`#L` line anchors are rejected.

`make docs-impact` is the answer to "which docs does this code change touch?".
It lists the documents that reference files changed against `HEAD` (or
`--base <rev>`) and warns when the diff removes a symbol one of them cites.
Treat that list as the re-read queue after changing code, and fix any reference
the change invalidated.

`Docs/PROJECT_ORIGIN.md` is a historical record: its quotation is immutable, so
correct a stale reference there by annotating outside the quote rather than
rewriting it. A single line can opt out of the symbol rule with
`<!-- docs-check: ignore -->`.

## Git and release workflow

- `main` is the canonical trunk.
- Use Conventional Commit messages, for example:
  - `feat: add frightened-ghost combo popups`
  - `fix: prevent tunnel wrap from skipping pellets`
  - `docs: record project governance`
  - `chore: refresh application icon`
- Keep commits coherent and reviewable. Do not mix unrelated refactors with
  gameplay changes.
- Run `swift build` and `swift run PacManChecks` before committing.
- Push to `origin/main`. The maintainer has authorized normal agent commits and
  pushes in this repository.
- Never force-push `main`, rewrite published history, or change remotes without
  explicit maintainer approval.
- Do not commit `.build/`, `dist/`, `.DS_Store`, or other generated artifacts.
  Distribution binaries belong in a release artifact, not source history.
- Do not tag or publish a GitHub Release unless the maintainer asks.

## Rendering and audio guidance

- Keep the presentation at the 896 × 1092 design resolution and letterbox it
  cleanly when the window aspect changes.
- Maintain 4× MSAA where supported and the existing triple-buffered vertex path.
- Respect the established palette, pixel font, arcade HUD, and scanline look.
- Screenshots in `Docs/` are user-facing documentation. Refresh them when a
  material visual change invalidates them.
- Sound effects are synthesized at launch. Keep the mute setting persisted and
  do not introduce audio files or network-streamed audio.

## Persistence and privacy

The app stores only two local preferences:

| Key | Purpose |
| --- | --- |
| `PacManArcadeHighScore` | Persistent local high score |
| `PacManArcadeMuted` | Sound preference |

Do not add analytics, identifiers, crash uploaders, or remote persistence. If a
new stored preference is unavoidable, document it here and in `SECURITY.md`.

## Legal and licensing

- PAC-MAN is a trademark of Bandai Namco Entertainment Inc. This is an
  unofficial fan tribute and must never be presented as affiliated with or
  endorsed by Bandai Namco.
- No open-source license has been selected for this repository. Do not add a
  license, relicense code, or claim reuse rights without explicit maintainer
  approval.
- Only contribute original code and generated art/audio, or material whose
  license is compatible and documented.

## Agent operating protocol

1. Read `AGENTS.md`, the origin record, and the relevant source before editing.
2. Inspect `git status` and preserve unrelated local work.
3. Make the smallest coherent change that satisfies the request.
4. Add or update checks for behavioral changes.
5. Build, run checks, and launch the app for presentation changes.
6. Update README/governance docs when behavior, controls, build steps, or
   policy changes, then run `make docs-check` and resolve the docs listed by
   `make docs-impact`.
7. Commit with a Conventional Commit message and push to `origin/main` when
   authorized.
8. Report what changed, what was verified, and any remaining risks or follow-up
   work.

Do not claim to have run something you did not run. If the environment prevents
a verification step, say exactly what was blocked.

## Definition of done

- [ ] Build succeeds without new warnings.
- [ ] `swift run PacManChecks` passes.
- [ ] `make docs-check` passes, and docs listed by `make docs-impact` were
      re-read after code changes.
- [ ] The app launches and renders correctly when presentation changed.
- [ ] Gameplay/controls documentation is current.
- [ ] Governance and origin records remain accurate.
- [ ] No generated binaries or secrets are staged.
- [ ] Change is committed and pushed, if authorized.

## When to stop and ask the maintainer

Ask before:

- changing licensing, repository visibility, or the canonical remote;
- adding third-party dependencies, assets, telemetry, or network access;
- making incompatible gameplay changes or altering the canonical maze;
- cutting a release, tag, or public distribution build;
- force-pushing or rewriting published history;
- implementing the level-256 kill screen or other large optional scope.

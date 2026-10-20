# Contributing to PAC-MAN — Metal Arcade

Thanks for your interest. This is a compact, dependency-free native macOS game,
and focused contributions are welcome.

Before changing anything, read [AGENTS.md](AGENTS.md),
[Docs/PROJECT_ORIGIN.md](Docs/PROJECT_ORIGIN.md), and
[GOVERNANCE.md](GOVERNANCE.md).

## Prerequisites

- macOS 13 or newer on a Metal-capable Mac
- Xcode or Apple Command Line Tools with Swift
- Git

No package-manager dependencies are required.

## Build and run

```bash
swift build
swift run PacManArcade
```

Build the distributable app and disk image:

```bash
make app
make dmg
open dist/PAC-MAN.app
```

Generated artifacts in `.build/` and `dist/` are deliberately not versioned.

## Verify changes

```bash
swift run PacManChecks
```

The checks executable is the regression suite. It covers the maze, movement,
ghost behavior, scoring, collisions, and state transitions. Add checks whenever
you change gameplay logic. Use the public API of `PacManGame`; do not add
test-only mutation hooks to production code.

For rendering, input, shader, or windowing changes, launching the app is
mandatory: Metal shaders compile at runtime, so a build alone cannot validate
them.

## Where to make changes

- **Simulation:** `Sources/PacManCore/` — Foundation only. Keep it independent
  of AppKit, Metal, MetalKit, and AVFoundation.
- **Presentation and platform:** `Sources/PacManArcade/`
- **Checks:** `Checks/main.swift`
- **Packaging:** `scripts/` and `Makefile`
- **User docs:** `README.md`
- **Governance docs:** `AGENTS.md`, `GOVERNANCE.md`, this file, `SECURITY.md`,
  and `Docs/PROJECT_ORIGIN.md`

## Quality bar

A contribution is ready when:

- `swift build` succeeds without new warnings;
- `swift run PacManChecks` passes;
- rendering changes were visually checked by running the app;
- gameplay invariants documented in `AGENTS.md` still hold, or the change
  explicitly updates them along with the checks and docs;
- no new runtime dependency, telemetry, network access, or non-original asset
  was introduced; and
- user-facing documentation and screenshots are current.

## Style

- Follow the existing Swift formatting and naming.
- Keep functions and types focused; the core should stay readable and testable.
- Prefer value types for state snapshots and explicit commands over public
  mutable state.
- Preserve the fixed-step 60 Hz simulation. Do not make movement or timing
  depend on display refresh rate.
- Keep procedural art and audio procedural. Do not add arcade ROM content,
  ripped sprites, recorded arcade audio, or copyrighted fonts.
- Avoid adding dependencies. Discuss a proposed dependency with the maintainer
  before writing code around it.

## Workflow

1. Open an issue for a substantial behavior change or new scope.
2. Branch from `main` using a descriptive name, for example
   `feat/frightened-combos` or `fix/tunnel-wrap`.
3. Make a coherent change with checks and docs.
4. Run the verification above.
5. Commit using a Conventional Commit message:
   - `feat: ...`
   - `fix: ...`
   - `docs: ...`
   - `perf: ...`
   - `refactor: ...`
   - `chore: ...`
6. Open a pull request describing the change, verification performed, and any
   known limitations.

Allowed direct pushes by repository agents are defined in `AGENTS.md`. Human
contributors should use pull requests unless the maintainer says otherwise.

## Reporting bugs

Use the repository issue tracker and include:

- macOS and Swift versions;
- steps to reproduce;
- expected and observed behavior;
- a screenshot or short recording for visual issues; and
- whether the issue reproduces after `make app` and a clean launch.

Please do not include secrets, personal information, or unredacted local paths
in public reports.

## Security

Do not open a public issue for a suspected vulnerability. Follow
[SECURITY.md](SECURITY.md).

## Conduct

Be constructive, specific, and respectful. Harassment, discrimination, personal
attacks, and deliberately disruptive behavior are not welcome. The maintainer
may moderate, close, or block participation to keep the project healthy.

## Licensing and intellectual property

PAC-MAN is a trademark of Bandai Namco Entertainment Inc. This is an unofficial
fan project and must not be presented as affiliated with or endorsed by Bandai
Namco.

No open-source license has been selected for this repository. Do not assume that
code, art, or audio may be reused or redistributed beyond this project. Only
submit original work or material with a documented compatible license. Adding a
license or changing the project's licensing requires explicit maintainer
approval.

For decisions about scope, releases, and repository policy, see
[GOVERNANCE.md](GOVERNANCE.md).

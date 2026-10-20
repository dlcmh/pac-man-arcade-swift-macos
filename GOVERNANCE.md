# Governance

This document defines how PAC-MAN — Metal Arcade is maintained, how decisions
are made, and how releases and legal obligations are handled. It is intentionally
lightweight for a small fan project.

- **Canonical repository:** <https://github.com/dlcmh/pac-man-arcade-swift-macos>
- **Canonical branch:** `main`
- **Maintainer:** David Chin ([@dlcmh](https://github.com/dlcmh))
- **Governance baseline:** 2026-10-20
- **Version covered:** 1.0

## Mission and scope

The project is a native, offline, procedurally generated macOS tribute to the
1980 Pac-Man arcade game. Its quality priorities are faithful arcade gameplay,
clean Swift architecture, a dependency-free Metal renderer, deterministic
behavior, and reproducible builds.

### In scope

- Pac-Man movement, maze traversal, dots, power pellets, fruit, scoring, lives,
  levels, high scores, and the established four-ghost behavior.
- Native macOS presentation, input, sound, and local persistence.
- Procedural art, audio, fonts, and app packaging.
- Simulation checks, documentation, and release tooling.

### Explicitly excluded unless re-scoped

- Network play, online leaderboards, accounts, telemetry, and remote content.
- Web, iOS, or other platform ports.
- Original arcade ROMs, sprites, fonts, audio, or other proprietary assets.
- The historical level-256 memory-corruption kill screen.
- Paid distribution or any claim of official affiliation with Bandai Namco.

Scope changes require the process described under **Decision making**.

## Roles

### Maintainer

The maintainer has final responsibility for:

- repository direction, roadmap, and scope;
- merging and publishing changes;
- releases, tags, signing, and distribution;
- licensing and trademark decisions;
- security response; and
- amendments to governance documents.

The current sole maintainer is [@dlcmh](https://github.com/dlcmh).

### Contributors

Contributors propose fixes, features, documentation, and tests through issues,
pull requests, or maintainer-authorized direct pushes. Contributions are
reviewed against the quality bar in [CONTRIBUTING.md](CONTRIBUTING.md) and the
architectural rules in [AGENTS.md](AGENTS.md).

### Users

Users may report bugs and request features through the GitHub issue tracker.
Security reports must follow [SECURITY.md](SECURITY.md).

## Decision making

The project uses a **maintainer-led** model:

- Day-to-day fixes and documentation improvements proceed through normal review.
- Substantial gameplay changes, new dependencies, platform changes, licensing
  changes, and releases require explicit maintainer approval.
- Discussion happens in the relevant GitHub issue or pull request so the record
  remains public where appropriate.
- When consensus is unclear, the maintainer makes the final decision and records
  the rationale.

Architectural invariants in [AGENTS.md](AGENTS.md) are considered settled policy
until changed through the governance amendment process.

## Quality gates

Changes to `main` are expected to pass:

1. `swift build`
2. `swift run PacManChecks`
3. A manual launch for any rendering, input, audio, shader, or windowing change
4. Review of user-facing documentation and governance accuracy

Generated binaries are not committed to source control. Distribution artifacts
are produced through `make app` and `make dmg` and published only when the
maintainer authorizes a release.

## Releases

Release versions follow semantic versioning for the application and its public
documentation.

A release requires the maintainer to:

1. confirm the checks and manual verification pass;
2. update the version in `Resources/Info.plist` and any `dist/` artifact naming;
3. confirm README, governance, and provenance records are current;
4. commit and tag the release if a tag is requested;
5. attach any `.app`/`.dmg` artifacts to a GitHub Release when distribution is
   intended; and
6. record notable changes and any compatibility notes.

Version 1.0 corresponds to the initial implementation commit and its immediately
following governance baseline. No Git tag or public GitHub Release was created
as part of the governance setup.

## Licensing and intellectual property

- **No open-source license has been selected for this repository.** Absent a
  separate license, default copyright applies and no permission to reuse or
  redistribute is granted.
- The maintainer reserves all licensing decisions. A license must not be added,
  changed, or implied by an agent or contributor without explicit approval.
- All committed code and generated art/audio must be original or properly
  licensed with attribution.
- Ripped or extracted assets from Pac-Man arcade hardware, ROMs, or official
  products are prohibited.
- PAC-MAN is a trademark of Bandai Namco Entertainment Inc. This project is an
  unofficial fan tribute and is not affiliated with or endorsed by Bandai Namco.
- Public descriptions must retain this disclaimer and must not imply official
  status.

See [Docs/PROJECT_ORIGIN.md](Docs/PROJECT_ORIGIN.md) for the commissioning record
and scope decisions.

## Security and privacy

The game is offline, has no accounts, and does not collect telemetry. Only a
local high score and mute preference are stored. Security handling is defined in
[SECURITY.md](SECURITY.md).

## Repository and remote policy

- `origin` is the canonical GitHub remote:
  <https://github.com/dlcmh/pac-man-arcade-swift-macos.git>
- `main` tracks `origin/main`.
- Force-pushing, rewriting published history, changing the canonical remote, or
  adding another release remote requires maintainer approval.
- Agents follow the commit and push rules in [AGENTS.md](AGENTS.md).

## Amendments

Governance changes are proposed as a pull request or explicit maintainer
instruction and require maintainer approval. The change should state why the
current rule is insufficient, what replaces it, and any migration impact.

The **Original request** quotation in
[Docs/PROJECT_ORIGIN.md](Docs/PROJECT_ORIGIN.md) is immutable. Historical
decisions may be annotated but must not be silently rewritten.

## Contact

Use the GitHub issue tracker for project questions and
[SECURITY.md](SECURITY.md) for vulnerabilities.

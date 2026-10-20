# Project Origin and Decision Record

This document preserves the request that created PAC-MAN — Metal Arcade and
records the decisions that shaped the delivered v1.0. It is a historical and
governance document. The **Original request** block below is immutable.

- **Project:** PAC-MAN — Metal Arcade
- **Repository:** <https://github.com/dlcmh/pac-man-arcade-swift-macos>
- **Commissioned by:** David Chin ([@dlcmh](https://github.com/dlcmh))
- **Commissioned:** 2026-10-20 08:56:39 (+08:00, Asia/Kuala_Lumpur)
- **Delivery agent:** DeepSeek Harness (deepseek-flash)
- **Initial implementation commit:** `88dd3db4ed92215490f1c0d92305c39a2c5208ea`
- **Initial public version:** 1.0

## Original request

The following is the human-authored request verbatim. Harness-supplied runtime
metadata that followed it is summarized separately and is not part of the
quote.

```text
reckon you can one-shot this game in clean Swift with Metal? Game description: "The original Pac-Man arcade game is a 1980 maze arcade game developed by Namco and released in North America by Midway.

Key Details

• Release Date: May 22, 1980 (Japan) / October 1980 (North America by Midway)
• Original Name: Puck Man (changed for international release to prevent vandalism of the cabinet's 'P' to an 'F')
• Creator/Designer: Toru Iwatani
• Core Objective: Guide Pac-Man through an enclosed maze to eat all the Pac-Dots while avoiding four ghosts: Blinky (red), Pinky (pink), Inky (cyan), and Clyde (orange).
• Power Pellets: Eating one of the four flashing Power Pellets temporarily turns the ghosts blue and vulnerable, allowing Pac-Man to eat them for bonus points.
• Famous Glitch: Level 256 features a memory overflow that corrupts the right half of the screen, making a "kill screen" that cannot be beaten normally.
• Where to Play Online: You can experience a browser version via the Original Pacman Game Online."
```

## Runtime context at commissioning

- Workspace: `/Users/dlcmh/dev/pac-man-arcade-swift-macos`
- Host platform: macOS 26 on Apple silicon, Swift 6.3.3 toolchain
- Interaction surface: DeepSeek Harness Web GUI
- File policy: workspace writes enabled
- Repository state at commissioning: empty local directory; no Git repository

These facts explain implementation choices and are not ongoing requirements.

## Requirements captured from the request

1. Deliver a playable, original-style Pac-Man arcade game in **clean Swift**
   with **Metal** rendering.
2. Implement the canonical maze loop: collect Pac-Dots while avoiding Blinky,
   Pinky, Inky, and Clyde.
3. Include the four flashing power pellets, ghost vulnerability, and bonus
   scoring for eating ghosts.
4. Deliver the result in one implementation pass rather than a mock-up or
   partial prototype.
5. Keep the work native to the supplied macOS workspace.

The brief's historical details were treated as context. The external online
play link was not an implementation requirement. The level-256 kill screen was
recognized as arcade history but not selected for emulation in v1.0.

## Delivered implementation

- Native macOS app built with Swift Package Manager, AppKit, MetalKit, Metal,
  and AVFoundation.
- Canonical 28 × 31 maze with 240 dots and 4 power pellets (244 total).
- Four ghosts with arcade-inspired targeting, scatter/chase phases, frightened
  behavior, house release, and eyes returning home.
- Buffered movement, tunnel wrapping, dot and ghost scoring, fruit, extra life,
  lives, levels, persistent high score, pause, death, and game-over flows.
- Entire presentation generated procedurally: neon wall renderer, character
  animation, custom 5 × 7 pixel font, fruit illustrations, CRT scanlines,
  application icon, and synthesized sound effects.
- Standalone simulation checks using only the public game API, including
  autopilot coverage for power pellets, collision/death, and game over.
- Ad-hoc-signed local app bundle and DMG packaging scripts.

## Explicit scope decisions

| Topic | Decision |
| --- | --- |
| Platform | Native macOS; no browser/WebAssembly build in v1.0. |
| Assets | No original arcade sprites, ROM data, fonts, or audio. Everything is procedural. |
| Level 256 kill screen | Documented as history; not emulated in v1.0. Requires explicit scoping. |
| Network | The game is fully offline. No leaderboards, telemetry, or downloads. |
| Persistence | Local `UserDefaults` only (high score and mute preference). |
| Licensing | No open-source license selected. All rights remain with the owner/contributors; see [GOVERNANCE.md](../GOVERNANCE.md). |
| Trademark | Unofficial fan tribute; not affiliated with or endorsed by Bandai Namco. |

## Verification record

The v1.0 baseline was built and launched on the commissioning host. The
simulation check suite passed 21,646 checks, covering:

- maze dimensions, pellet totals, tunnel wrapping, and full pellet reachability;
- ghost-eye routing into the house;
- start, ready, play, pause, death, and restart state transitions;
- dots, high score, wall stops, and buffered turns;
- ghost-house release timing and a 60-second movement soak test;
- an autopilot run reaching a power pellet; and
- ghost collision, life loss, and complete game over.

Visual verification used window captures recorded in [Docs/](../Docs/).

## Governance directive

The governance baseline was requested in a follow-up on 2026-10-20:

```text
create agents md and any other necessary governance docs, document the original query that started this project, set upstream to https://github.com/dlcmh/pac-man-arcade-swift-macos.git, commit and push at will - you have the con
```

This established [AGENTS.md](../AGENTS.md), [CONTRIBUTING.md](../CONTRIBUTING.md),
[GOVERNANCE.md](../GOVERNANCE.md), [SECURITY.md](../SECURITY.md), and this record.
The canonical remote is `origin`, and `main` tracks `origin/main`.

## Record maintenance

- Do not edit the **Original request** quotation.
- Append material decisions rather than silently rewriting history.
- Update the verification section when the release baseline changes.
- Changes to governance itself follow [GOVERNANCE.md](../GOVERNANCE.md).

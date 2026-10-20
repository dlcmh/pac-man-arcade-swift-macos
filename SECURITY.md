# Security Policy

## Supported versions

| Version | Supported |
| --- | --- |
| `main` / 1.x | Yes |
| Older snapshots | No |

The project is a local-only fan game. There is no server component and no
network access by default.

## Reporting a vulnerability

Please **do not open a public GitHub issue** for a suspected security
vulnerability.

Report it privately through GitHub's private vulnerability reporting:

<https://github.com/dlcmh/pac-man-arcade-swift-macos/security/advisories/new>

If private advisories are unavailable, contact the maintainer
[@dlcmh](https://github.com/dlcmh) through GitHub and request a private channel.
Do not include exploit details in a public issue.

In your report, include:

- the affected version or commit;
- macOS, Swift, and hardware details;
- a concise description of the issue and its impact;
- reproduction steps or a minimal proof of concept; and
- any suggested mitigation.

## Response expectations

This is a volunteer-maintained fan project. The maintainer will make a best
effort to acknowledge reports, assess severity, and coordinate a fix and
disclosure. No response-time or remediation SLA is offered, and no bug bounty is
available.

Please allow reasonable time for a fix before public disclosure. The maintainer
will coordinate disclosure timing with the reporter.

## Scope

The intended attack surface is deliberately small:

- a native macOS application that runs locally;
- no network requests, telemetry, accounts, or remote configuration;
- no third-party runtime dependencies; and
- local `UserDefaults` only for high score and mute state.

Reports are in scope when they describe a concrete security impact in this
repository, for example unsafe packaging, unexpected data access, a compromised
build path, or a dependency/asset issue that enters the app.

Out of scope includes:

- social engineering and physical access to an unlocked machine;
- vulnerabilities in macOS, Swift, Metal, or the user's toolchain that are not
  caused by this project;
- issues requiring a malicious local user to alter the app bundle or the user's
  preferences without a trust-boundary crossing;
- denial-of-service from manually editing local files;
- trademark or licensing questions (see [GOVERNANCE.md](GOVERNANCE.md)); and
- reports against unofficial forks or modified distributions.

## Local data and privacy

The app stores only:

| Preference key | Data | Purpose |
| --- | --- | --- |
| `PacManArcadeHighScore` | Integer | Local high score |
| `PacManArcadeMuted` | Boolean | Sound preference |

There is no analytics, telemetry, crash uploader, advertising, or remote
persistence. The game does not transmit gameplay data. Users can remove local
preferences with `defaults delete dev.dlcmh.pacman-arcade`.

## Build integrity

- Builds are produced from source with `swift build` or `make app`.
- The app bundle is ad-hoc signed for local use; it is not Developer ID signed
  or notarized for general distribution.
- No prebuilt binary is committed to the repository.
- Do not download or run third-party modified builds claiming to be official.
- The canonical source is
  <https://github.com/dlcmh/pac-man-arcade-swift-macos>.

## Dependency policy

The project currently has no third-party runtime dependencies. Any proposed
dependency requires maintainer approval and a review of its security, licensing,
and maintenance impact.

## Legal and project context

See [GOVERNANCE.md](GOVERNANCE.md) for licensing, trademark, and project policy.

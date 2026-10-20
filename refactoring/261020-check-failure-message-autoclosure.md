# 2026-10-20 — Deferring `check` failure messages with `@autoclosure`

Evaluation of a proposed signature change to the simulation-check helper.

- **Project:** PAC-MAN — Metal Arcade
- **Recorded:** 2026-10-20 (+08:00, Asia/Kuala_Lumpur)
- **Subject:** [`Checks/main.swift:6`](../Checks/main.swift#L6)
- **Proposal:** change `_ message: String` to `_ message: @autoclosure () -> String`
- **Outcome:** **declined.** No code change. The technique is sound; the benefit
  is zero in this codebase, and the stated performance rationale does not hold.

## The proposal

The claim, in short: because `message` is an eagerly evaluated `String`, every
call to `check` has to build the message even when the assertion passes. Making
the parameter an `@autoclosure` would defer construction until failure, matching
what `assert`, `XCTAssert`, and Swift Testing's `#expect` do:

```swift
func check(_ condition: @autoclosure () -> Bool,
           _ message: @autoclosure () -> String) {
    checks += 1
    if !condition() {
        print("FAIL: \(message())")   // evaluated only on failure
        exit(1)
    }
}
```

## Verdict

The mechanism is real and the precedent is correct: `assert`'s message parameter
is indeed `@autoclosure () -> String`. But three facts make the change worthless
here, and one of them makes the performance argument specifically false.

1. **No call site interpolates.** All 43 call sites pass string literals, so
   there is no string-building work to defer.
2. **A literal costs nothing to pass.** It refers to static storage; the
   optimizer folds the whole call away.
3. **The harness is not a hot loop.** `PacManChecks` runs 21,646 assertions in
   ~19 ms once, then exits. The proposal's "every single frame or step of your
   game loop" describes `PacManGame`, not the checks binary. The two are not the
   same code path.

## What the proposal gets right

- **Deferring an interpolated message is a genuine, large win.** Measured at
  ~100 ns saved per call (see below).
- **The standard-library precedent is accurate.**
- **The general principle is good advice** for assertion helpers whose messages
  are routinely interpolated. That is simply not this helper.

## Where the argument does not transfer

### The call-site census

| Metric | Value |
| --- | --- |
| `check(...)` call sites in `Checks/main.swift` | 43 |
| Call sites whose message uses string interpolation | 0 |
| Assertions executed at runtime | 21,646 |
| Wall-clock runtime of `.build/debug/PacManChecks` | 18.6 ms median (15 runs) |

With no interpolated messages, the deferral has nothing to defer.

### The cost is in the wrong place

The suite spends its ~19 ms in the simulation — a 60-second soak at 60 Hz plus
autopilot and death sequences — not in formatting 43 literals. Even under the
most pessimistic assumption (every one of the 21,646 messages interpolated), the
total saving is ~2 ms of an 18.6 ms run.

## Measurements

Two message forms, same call site, `swiftc -O` and `swiftc -Onone`, 2,000,000
iterations each, Apple M5 / arm64, Swift 6.3.3.

**Optimized (`-O`) — ns per call:**

| Message form | plain `String` | `@autoclosure () -> String` |
| --- | --- | --- |
| string literal | 0.0 (compiled away) | ~1.1 |
| interpolated | 92–103 | ~1.1 |

**Unoptimized (`-Onone`) — ns per call:**

| Message form | plain `String` | `@autoclosure () -> String` |
| --- | --- | --- |
| string literal | ~66 | ~61 |
| interpolated | ~166 | ~65 |

Three engineering points fall out of this:

- **The payoff is entirely a function of the message form.** Interpolation is
  the only thing worth deferring. Literals are free.
- **The sign of the change flips with the optimization level.** Under `-O` the
  autoclosure is pure overhead for literals (~1 ns of closure construction in
  exchange for nothing). Under `-Onone` both forms cost roughly the same, so it
  is a wash rather than a win.
- **`swift run PacManChecks` builds `-Onone`,** so the second table is the one
  that applies to this repository — and it says the literal cases are
  indistinguishable while the simulation dominates the run.

## The semantic caveat the proposal omits

Changing the parameter to `@autoclosure` changes *when* the message is
evaluated, which is a behaviour change, not a pure optimisation: the message
expression is evaluated after `condition()`, at failure time. If a message
interpolates state that the condition itself mutates, the printed value becomes
post-condition state. For a check harness that is usually desirable, but it is
not free, and it should be chosen deliberately rather than presented as
cost-free.

## What would actually improve `check`

Ranked by value, if the helper is worth touching at all:

1. **Leave the signature alone.** It is provably free at 43 literal call sites.
2. **If changed, justify it as future-proofing** for interpolated messages — not
   as a performance fix — and land it as its own `test:` commit, per the
   smallest-coherent-change rule in [`AGENTS.md`](../AGENTS.md).
3. **Capture failure context instead.** The real ergonomic gap is that
   `check` prints only a hand-written string and `exit(1)` on the first failure:
   no source location, no operand values. That is the part of `#expect` that
   users actually feel, and it would make failure messages easier to write and
   narrower to read.

## How the timings were measured

**Why isolate the message forms.** Timing the real checks binary would measure
the simulation, and timing only the refactored helper would answer neither
interesting question. The two questions are: does deferral cost anything when
the message is a literal, and does it save anything when the message
interpolates? So the benchmark holds the call site fixed and varies only the
message form and the parameter type, which makes the difference attributable.

**The harness.** A throwaway Swift file, compiled twice — once with `-O` and once
with `-Onone` — because the optimization level turned out to change the
conclusion. Both helpers are marked `@inline(never)` so the comparison does not
depend on whether the compiler chooses to inline `check`; without that, `-O`
would fold the entire loop away even more aggressively than it already does.

```swift
import Foundation

@inline(never) func checkPlain(_ c: @autoclosure () -> Bool, _ m: String) {
    if !c() { print(m); exit(1) }
}
@inline(never) func checkAuto(_ c: @autoclosure () -> Bool,
                              _ m: @autoclosure () -> String) {
    if !c() { print(m()); exit(1) }
}

let n = 2_000_000
var sink = 0.0

var t0 = DispatchTime.now().uptimeNanoseconds
for _ in 0..<n { checkPlain(true, "Pac-Man position remains finite") }
let literalPlain = DispatchTime.now().uptimeNanoseconds - t0

t0 = DispatchTime.now().uptimeNanoseconds
for _ in 0..<n { checkAuto(true, "Pac-Man position remains finite") }
let literalAuto = DispatchTime.now().uptimeNanoseconds - t0

t0 = DispatchTime.now().uptimeNanoseconds
for i in 0..<n { sink += 1; checkPlain(true, "Score is \(i), pellet \(i * 3)") }
let interpPlain = DispatchTime.now().uptimeNanoseconds - t0

t0 = DispatchTime.now().uptimeNanoseconds
for i in 0..<n { sink += 1; checkAuto(true, "Score is \(i), pellet \(i * 3)") }
let interpAuto = DispatchTime.now().uptimeNanoseconds - t0

let per = { (t: UInt64) in Double(t) / Double(n) }   // ns per call
print(per(literalPlain), per(literalAuto), per(interpPlain), per(interpAuto), sink)
```

The condition is the constant `true` in every loop so that only message handling
is under test; `sink` keeps the interpolation inputs live so the optimizer cannot
eliminate the interpolated cases, and it is printed to prove they ran.

**The harness itself.** Cheap microbenchmarks, so correctness of the methodology
matters more than statistical rigour: run three times per build to confirm
stability (the numbers above are stable within a few percent), and report
medians. Separately, the real binary was run 15 times under Python's
`time.perf_counter`, discarding nothing:

```python
import subprocess, time, statistics
ts = []
for _ in range(15):
    t = time.perf_counter()
    subprocess.run([".build/debug/PacManChecks"], capture_output=True, text=True)
    ts.append(time.perf_counter() - t)
print(min(ts)*1000, statistics.median(ts)*1000, max(ts)*1000)   # 18.0 / 18.6 / 23.7 ms
```

`perf_counter` wraps the whole process — exec, package load, simulation, all
21,646 assertions — which is the number a contributor actually experiences.

**Threats to validity.** These are directional numbers, not a bench suite:

- Single machine, single toolchain. Absolute nanoseconds will differ elsewhere;
  the *ratios* and the sign are what the decision rests on.
- Under `-O` the literal cases optimise so completely that the measurement is
  floor-limited by the clock, so "0.0 ns/call" means "below timer resolution",
  not a precise zero.
- The benchmark loops are synthetic. They are appropriate here because the
  comparison is between two signatures at an identical call site, not an
  estimate of production cost.
- The benchmark source is not committed. It is reproduced above in full so the
  measurements can be re-run; a committed benchmark would need a stable
  comparison target to be worth its maintenance cost.

## Decision

No change to `Checks/main.swift`. The existing signature is correct for a
literal-only harness, and the proposal's performance premise — that messages are
built on every passing call — is true of interpolated messages only, of which
there are none. Revisit if `check` starts receiving interpolated messages in a
hot loop, which is to say: probably never.

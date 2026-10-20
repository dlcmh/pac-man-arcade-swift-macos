# Refactoring

Dated records of refactors that were proposed and evaluated. Each entry captures
the evidence behind the decision — measurements, call-site counts, and the
reasoning — so that a rejected idea does not have to be re-litigated from
memory, and an accepted one has a stated rationale to check the code against.

Documents are listed newest first, by the **Last updated** date recorded in each
file.

| Document | Last updated | Decision |
| --- | --- | --- |
| [Deferring `check` failure messages with `@autoclosure`](check-failure-message-autoclosure.md) | 2026-10-20 | Declined — no interpolated messages, no measurable payoff |

## Adding an entry

1. Name the file after the change, not the date (`check-failure-message-autoclosure.md`),
   so links survive re-edits.
2. Record both a `Recorded` and a `Last updated` date in the document's metadata
   block, and keep them current.
3. Insert the document into the table above in descending date order.

To confirm the date to record, use the commit that last touched the file:

```bash
git log -1 --format=%cs -- Docs/refactoring/<file>.md
```

The in-file date is authoritative because it survives cloning, where file
modification times do not. The two should agree with the command above.

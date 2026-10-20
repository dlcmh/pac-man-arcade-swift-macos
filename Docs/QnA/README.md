# Q&A

Questions about how **PAC-MAN — Metal Arcade** works, with answers grounded in
the source. Each entry is a standalone document named after the question and
cites the files and symbols that implement the behavior, so the references
survive unrelated edits.

Documents are listed newest first, by the **Last updated** date recorded in each
file. When dates are equal, the most recently added question comes first.

| Question | Last updated | Covers |
| --- | --- | --- |
| [How does the 5×7 procedural font work?](pixel-font.md) | 2026-10-20 | Glyph bitmaps, quad-based text, scaling, glow, and the asset-free font pipeline |
| [How does PacManCore work, and what software-engineering principles does it demonstrate?](pacmancore-architecture.md) | 2026-10-20 | The headless simulation, its adapter boundary, determinism, and the principles behind the split |
| [What is attract mode?](attract-mode.md) | 2026-10-20 | The idle title screen, its frozen game state, start input, and animated overlay |
| [Is Metal used for all computations?](metal-computations.md) | 2026-10-20 | The CPU-simulation / GPU-rendering split and why it exists |
| [What is BFS?](breadth-first-search.md) | 2026-10-20 | Breadth-first search and the ghost-house distance field |
| [How do the ghosts know how to hunt and move towards Pac-Man?](ghost-hunting-and-movement.md) | 2026-10-20 | Target points, greedy tile-center choices, ghost personalities, scatter, frightened, and eyes |

## Adding an entry

1. Name the file after the question, not the date
   (`ghost-hunting-and-movement.md`), so links survive re-edits.
2. Start the document with the question as its `#` heading, then record both a
   `Recorded` and a `Last updated` date in the metadata block, matching the
   style of the existing entries.
3. Insert the document into the table above in descending date order.
4. Cite code by file and symbol, never by line number, and run `make docs-check`
   before committing. The convention is defined in
   [`AGENTS.md`](../../AGENTS.md#documentation-and-code-references).

To confirm the date to record, use the commit that last touched the file:

```bash
git log -1 --format=%cs -- Docs/QnA/<file>.md
```

The in-file date is authoritative because it survives cloning, where file
modification times do not. The two should agree with the command above.

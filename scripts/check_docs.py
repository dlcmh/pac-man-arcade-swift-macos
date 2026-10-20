#!/usr/bin/env python3
"""Validate documentation links and code references.

Why this exists
---------------
Prose that points at "Game.swift line 312" rots silently: insert ten lines above
the function and the link still resolves, just to the wrong code. Documentation
in this repository therefore cites a *file plus a symbol name* instead of a line
number. That reference survives unrelated edits, and it can be checked by a
machine.

Rules enforced
--------------
1. Every relative link resolves to a file that exists.
2. No `#L<number>` line anchors anywhere. Cite the symbol instead.
3. A `#fragment` on a Markdown target must match a real heading.
4. Every link into Swift source (`Sources/`, `Checks/`) or a script must be
   followed, in the same sentence or bullet, by an inline-code symbol that
   occurs in the linked file.

Usage
-----
    python3 scripts/check_docs.py              # validate everything
    python3 scripts/check_docs.py --changed    # validate, then report which
                                               # docs reference changed files
    python3 scripts/check_docs.py --base main  # compare against another ref

`--changed` never fails because a referenced file changed; it prints the list a
human or agent should re-read. Validation errors always exit 1.

Opt out of rule 4 on a single line with an HTML comment:

    <!-- docs-check: ignore -->

Standard library only: this project has no third-party dependencies.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CODE_PREFIXES = ("Sources/", "Checks/")
CODE_FILES = ("Package.swift", "Makefile")
SKIP_DIRS = {".build", ".git", "dist", "Resources"}

LINK_RE = re.compile(r"(?<!!)\[([^\]]*)\]\(([^)\s]+)\)")
INLINE_CODE_RE = re.compile(r"`([^`]+)`")
LIST_OR_HEADING_RE = re.compile(r"^\s*(#{1,6}\s|[-*+]\s|\d+\.\s|\||```)")
DECL_RE = re.compile(
    r"^\s*(?:@\w+\s+)*(?:(?:public|private|internal|fileprivate|open|final|"
    r"static|class|mutating|nonmutating|override|convenience|required|"
    r"indirect|lazy|weak|unowned)\s+)*"
    r"(?:func|var|let|struct|enum|class|actor|protocol|extension|typealias|"
    r"case|init)\s+([A-Za-z_][A-Za-z0-9_]*)"
)


class Doc:
    def __init__(self, path: str) -> None:
        self.path = path
        self.lines = open(os.path.join(ROOT, path), encoding="utf-8").read().splitlines()
        self.fenced = [False] * len(self.lines)
        in_fence = False
        for index, line in enumerate(self.lines):
            if line.lstrip().startswith("```"):
                self.fenced[index] = True
                in_fence = not in_fence
            else:
                self.fenced[index] = in_fence


def repo_docs() -> list[Doc]:
    docs = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS and not d.startswith("."))
        for name in sorted(filenames):
            if not name.endswith(".md"):
                continue
            path = os.path.relpath(os.path.join(dirpath, name), ROOT)
            docs.append(Doc(path))
    return docs


def source_files() -> list[str]:
    files = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS and not d.startswith("."))
        for name in filenames:
            if name.endswith((".swift", ".sh", ".py")):
                files.append(os.path.relpath(os.path.join(dirpath, name), ROOT))
    return files


def heading_slugs(doc: Doc) -> set[str]:
    """Approximate GitHub's heading anchors, including -1 duplicate suffixes."""
    slugs: set[str] = set()
    seen: dict[str, int] = {}
    in_fence = False
    for line in doc.lines:
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence or not line.startswith("#"):
            continue
        text = line.lstrip("#").strip()
        if not text:
            continue
        text = re.sub(r"`([^`]*)`", r"\1", text)
        text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
        text = text.lower()
        text = re.sub(r"[^\w\- ]", "", text)
        slug = text.replace(" ", "-")
        count = seen.get(slug, 0)
        seen[slug] = count + 1
        slugs.add(slug if count == 0 else f"{slug}-{count}")
    return slugs


def is_code_target(target: str) -> bool:
    return target.startswith(CODE_PREFIXES) or target in CODE_FILES


def link_context(doc: Doc, index: int, end_column: int) -> str:
    """Text from the end of a link to the end of its sentence or bullet."""
    parts = [doc.lines[index][end_column:]]
    cursor = index + 1
    while cursor < len(doc.lines):
        line = doc.lines[cursor]
        if not line.strip() or LIST_OR_HEADING_RE.match(line):
            break
        parts.append(line)
        cursor += 1
    return " ".join(parts)


def cited_symbol(text: str) -> str | None:
    for match in INLINE_CODE_RE.finditer(text):
        raw = match.group(1).strip()
        if raw.endswith((".swift", ".md")) or "/" in raw or raw.startswith("#L"):
            continue
        name = raw.split("(")[0].strip().split(".")[-1]
        name = name.rstrip(".,;")
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name or ""):
            return name
    return None


def symbol_in_file(symbol: str, path: str) -> bool:
    try:
        text = open(os.path.join(ROOT, path), encoding="utf-8").read()
    except OSError:
        return False
    return re.search(rf"\b{re.escape(symbol)}\b", text) is not None


def validate() -> tuple[list[str], dict[str, list[tuple[str, str]]]]:
    """Return (errors, references) where references maps file -> [(doc, symbol)]."""
    errors: list[str] = []
    references: dict[str, list[tuple[str, str]]] = {}
    slugs: dict[str, set[str]] = {}
    known_files = set(source_files())
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS and not d.startswith(".")]
        for name in filenames:
            known_files.add(os.path.relpath(os.path.join(dirpath, name), ROOT))

    for doc in repo_docs():
        for index, line in enumerate(doc.lines):
            if doc.fenced[index]:
                continue
            for match in LINK_RE.finditer(line):
                label, target = match.group(1), match.group(2)
                if target.startswith(("http://", "https://", "mailto:", "#")):
                    continue
                path, _, fragment = target.partition("#")
                where = f"{doc.path}:{index + 1}"
                resolved = (
                    os.path.normpath(os.path.join(os.path.dirname(doc.path), path))
                    if path
                    else doc.path
                )
                if not os.path.exists(os.path.join(ROOT, resolved)):
                    errors.append(f"{where}: link target does not exist: {target}")
                    continue

                if fragment:
                    if re.match(r"L\d+", fragment):
                        errors.append(
                            f"{where}: line anchor '#{fragment}' is not allowed; "
                            "link to the file and cite the symbol"
                        )
                        continue
                    if resolved.endswith(".md"):
                        if resolved not in slugs:
                            slugs[resolved] = heading_slugs(Doc(resolved))
                        if fragment not in slugs[resolved]:
                            errors.append(
                                f"{where}: no heading matches anchor '#{fragment}' in {resolved}"
                            )

                if not is_code_target(resolved):
                    continue

                if "docs-check: ignore" in line:
                    continue

                context = link_context(doc, index, match.end())
                symbol = cited_symbol(context)
                if symbol is None and label.strip():
                    # A link whose visible text is itself a symbol, e.g.
                    # [`drawPrimitives`](...), names the symbol in the label.
                    symbol = cited_symbol(f"`{label}`") if "`" in label else None
                if symbol is None:
                    errors.append(
                        f"{where}: link to {resolved} must cite a symbol in backticks "
                        "(for example `updateGhosts`) so it can be verified"
                    )
                    continue
                if not symbol_in_file(symbol, resolved):
                    errors.append(
                        f"{where}: '{symbol}' does not occur in {resolved}; "
                        "the reference has drifted or the symbol was renamed"
                    )
                    continue
                references.setdefault(resolved, []).append((doc.path, symbol))
    return errors, references


def git(*args: str) -> str:
    result = subprocess.run(
        ["git", *args], cwd=ROOT, capture_output=True, text=True, check=False
    )
    return result.stdout


def changed_files(base: str) -> list[str]:
    files = [line for line in git("diff", "--name-only", base).splitlines() if line]
    files += [
        line
        for line in git("ls-files", "--others", "--exclude-standard").splitlines()
        if line
    ]
    return sorted(set(files))


def removed_symbols(base: str) -> dict[str, set[str]]:
    """Declaration names removed by the diff, per file. Used as a review hint."""
    removed: dict[str, set[str]] = {}
    current = None
    for line in git("diff", "-U0", base).splitlines():
        if line.startswith("+++ b/"):
            current = line[6:]
            continue
        if line.startswith("---") or not current:
            continue
        if line.startswith("-"):
            match = DECL_RE.match(line[1:])
            if match:
                removed.setdefault(current, set()).add(match.group(1))
    return removed


def report_changed(base: str, references: dict[str, list[tuple[str, str]]]) -> None:
    files = changed_files(base)
    if not files:
        print("No changed files.")
        return
    removed = removed_symbols(base)
    hits = 0
    print(f"Documentation impact of changes against {base}:")
    for path in files:
        docs = references.get(path)
        if not docs:
            continue
        hits += 1
        by_doc: dict[str, list[str]] = {}
        for doc, symbol in docs:
            by_doc.setdefault(doc, []).append(symbol)
        print(f"\n  {path}")
        for doc, symbols in sorted(by_doc.items()):
            print(f"    {doc}: " + ", ".join(f"`{s}`" for s in sorted(set(symbols))))
        gone = removed.get(path, set())
        cited = {symbol for _, symbol in docs}
        for symbol in sorted(gone & cited):
            print(
                f"    WARNING: the diff removes `{symbol}`, which this doc cites; "
                "update the reference"
            )
    if not hits:
        print("  No documentation references the changed files.")
    else:
        print("\nRe-read the docs above before committing.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--changed",
        action="store_true",
        help="also report docs that reference files changed against --base",
    )
    parser.add_argument(
        "--base",
        default="HEAD",
        help="git revision to diff against for --changed (default: HEAD)",
    )
    args = parser.parse_args()

    errors, references = validate()
    if errors:
        for error in errors:
            print(f"ERROR {error}")
        print(f"\nFAIL: {len(errors)} documentation problem(s)")
        return 1
    print(
        f"OK: {len(references)} code file(s) referenced by docs, "
        "all links and cited symbols resolve"
    )
    if args.changed:
        print()
        report_changed(args.base, references)
    return 0


if __name__ == "__main__":
    sys.exit(main())

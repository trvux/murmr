#!/bin/sh
# Keeps the English and Vietnamese documents in step. For each pair (X.md and X.vi.md) it checks that both exist, that
# each links to the other in its first line, and that they have the same structure: headings per level, code blocks,
# table rows, images and links (a link to a .vi.md file counts as the same link as its .md twin). It cannot tell whether
# the sentences mean the same; it tells you when one side gained a section, a table row or a link that the other lacks.
#
#   scripts/check-docs.sh
set -eu
cd "$(dirname "$0")/.."

python3 - <<'EOF'
import re, sys

PAIRS = [
    ("README.md", "README.vi.md"),
    ("PRIVACY.md", "PRIVACY.vi.md"),
    ("docs/DEVELOPMENT.md", "docs/DEVELOPMENT.vi.md"),
]

def shape(text):
    """What must match between the two languages."""
    lines = text.splitlines()
    in_code = False
    headings, tables, codes = [], [], 0
    table_rows = 0
    for line in lines:
        if line.startswith("```"):
            if not in_code:
                codes += 1
            in_code = not in_code
            continue
        if in_code:
            continue
        m = re.match(r"^(#{1,6}) ", line)
        if m:
            headings.append(len(m.group(1)))
        if line.startswith("|"):
            table_rows += 1
        elif table_rows:
            tables.append(table_rows)
            table_rows = 0
    if table_rows:
        tables.append(table_rows)
    body = re.sub(r"```.*?```", "", text, flags=re.S)
    targets = re.findall(r"\]\(([^)\s]+)", body) + re.findall(r'(?:src|srcset|href)="([^"]+)"', body)
    norm = []
    for t in targets:
        t = t.split("#")[0].replace(".vi.md", ".md")  # a heading anchor is written in its own language
        t = re.sub(r"/(en|vi)/", "/<lang>/", t)  # pictures live in docs/en/ and docs/vi/ with the same names
        if t.startswith("https://img.shields.io/badge/"):
            t = "https://img.shields.io/badge/*"  # the words on a static badge are translated
        if t:
            norm.append(t)
    return headings, tables, codes, sorted(norm)

problems = 0
def bad(msg):
    global problems
    problems += 1
    print("  - " + msg)

for en, vi in PAIRS:
    print(f"{en}  <->  {vi}")
    try:
        t_en, t_vi = open(en, encoding="utf-8").read(), open(vi, encoding="utf-8").read()
    except FileNotFoundError as e:
        bad(f"missing file: {e.filename}")
        continue
    first_en, first_vi = t_en.splitlines()[0], t_vi.splitlines()[0]
    if vi.split("/")[-1] not in first_en:
        bad(f"{en}: the first line should link to {vi}")
    if en.split("/")[-1] not in first_vi:
        bad(f"{vi}: the first line should link to {en}")
    a, b = shape(t_en), shape(t_vi)
    if a[0] != b[0]:
        bad(f"headings differ: {len(a[0])} in English, {len(b[0])} in Vietnamese (levels {a[0]} vs {b[0]})")
    if a[1] != b[1]:
        bad(f"table sizes differ: rows per table {a[1]} vs {b[1]}")
    if a[2] != b[2]:
        bad(f"code blocks differ: {a[2]} vs {b[2]}")
    if a[3] != b[3]:
        only_en = [x for x in a[3] if x not in b[3]]
        only_vi = [x for x in b[3] if x not in a[3]]
        bad(f"links or images differ. only in English: {only_en}; only in Vietnamese: {only_vi}")

if problems:
    print(f"\n{problems} problem(s): the two languages have drifted apart.")
    sys.exit(1)
print("\ndocs: the English and Vietnamese documents match in structure.")
EOF

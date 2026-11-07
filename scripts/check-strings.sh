#!/bin/sh
# Keeps the app's two interface languages complete. The words in the code are Vietnamese and are the keys; the English
# is in app/Resources/en.lproj/Localizable.strings (see L10n.swift). This fails when:
#   - a Vietnamese word that reaches the screen has no English entry;
#   - such a word is written where nothing translates it (a bare "..." in a ternary, a `return`, an assignment): wrap it in tr("...");
#   - a literal has a value in it (\(x)) outside tr("...") / Say("..."): the value is mixed in before the lookup, so the
#     English entry could never match. Write tr("... %@", x) and keep %@ in the entry.
# It warns about English entries nothing uses. A line can opt out with the comment `l10n-ok`.
#
#   scripts/check-strings.sh
set -eu
cd "$(dirname "$0")/.."

python3 - <<'EOF'
import glob, json, re, subprocess, sys

SRC = sorted(glob.glob("app/Sources/MurmrStream/*.swift"))
SKIP = {"Snapshot.swift", "Theme.swift"}  # developer hooks and brand art (the art is handled by its own language parameter)
EN_FILE = "app/Resources/en.lproj/Localizable.strings"
SAME = {"Model", "Murmr", "Murmr Stream", "STREAM", "English", "Tiếng Việt", "fn", "Esc", "Return", "Space", "Tab", "Delete",
        "Keychain", "Whisper", "DeepSeek", "Claude", "OpenAI", "Gemini", "Kimi", "OpenRouter", "Ollama", "Accessibility"}  # same in both languages
VN = re.compile(r"[àáảãạăắằẳẵặâấầẩẫậèéẻẽẹêếềểễệìíỉĩịòóỏõọôốồổỗộơớờởỡợùúủũụưứừửữựỳýỷỹỵđĐÀÁẢÃẠĂẮẰẲẴẶÂẤẦẨẪẬÈÉẺẼẸÊẾỀỂỄỆÌÍỈĨỊÒÓỎÕỌÔỐỒỔỖỘƠỚỜỞỠỢÙÚỦŨỤƯỨỪỬỮỰỲÝỶỸỴ]")

# calls whose first string argument is looked up by SwiftUI itself (a literal there is a localisation key) or by us
LOOKED_UP = ("Text(", "Button(", "Label(", "Toggle(", "Picker(", "TextField(", "SecureField(", "Section(", "Link(", "Eyebrow(",
             ".accessibilityLabel(", "title:", "detail:", "subtitle:", "placeholder:", "label:", "heading(", "bullet(", "demoStep(",
             "note(", "emptyNote(", "ExternalLink(", "SettingRow(", "OutlineButton(", "InkButton(")
EXPLICIT = ("tr(", "Say(", "L10n.tr(")

def literals(text):
    """Yield (line, before, raw) for every "..." literal outside comments."""
    i, n, line = 0, len(text), 1
    line_start = 0
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1; line_start = i + 1; i += 1; continue
        if text.startswith("//", i):
            while i < n and text[i] != "\n": i += 1
            continue
        if text.startswith("/*", i):
            j = text.find("*/", i + 2); j = n if j < 0 else j + 2
            line += text.count("\n", i, j); i = j; continue
        if c == '"':
            start, depth, j, raw = i, 0, i + 1, []
            while j < n:
                d = text[j]
                if d == "\\" and j + 1 < n:
                    if text[j + 1] == "(":
                        depth = 1; raw.append("\\("); j += 2
                        while j < n and depth:  # skip the expression of an interpolation, which may hold quotes
                            if text[j] == "(": depth += 1
                            elif text[j] == ")": depth -= 1
                            raw.append(text[j]); j += 1
                        continue
                    raw.append(text[j:j + 2]); j += 2; continue
                if d == '"': break
                raw.append(d); j += 1
            before = text[line_start:start]
            yield line, before, "".join(raw)
            line += text.count("\n", start, j); i = j + 1; continue
        i += 1

def unescape(s):
    s = re.sub(r"\\\(.*?\)(?=[^)]|$)", "%@", s) if "\\(" in s else s
    return s.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")

en = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", EN_FILE]))
norm = lambda k: k  # exact: tr("... %@", x) looks the key up as written, so the entry must say %@ too
en_keys = {norm(k) for k in en}
used, errors = set(), []

def err(path, line, msg): errors.append(f"{path}:{line}: {msg}")

for path in SRC:
    if path.split("/")[-1] in SKIP: continue
    text = open(path, encoding="utf-8").read()
    lines = text.splitlines()
    for line, before, raw in literals(text):
        if "l10n-ok" in lines[line - 1]: continue
        has_value = "\\(" in raw
        key = norm(unescape(raw))
        stripped = before.rstrip()
        explicit = stripped.endswith(EXPLICIT)
        looked_up = explicit or stripped.endswith(LOOKED_UP) or re.search(r"(title|detail|subtitle|placeholder|label):\s*$", stripped)
        vi = bool(VN.search(key))
        words = bool(re.search(r"[A-Za-zÀ-ỹ]{2}", key))
        if not words or key in SAME: continue
        # a plain word with no Vietnamese letters (an id, a key name) is not interface text unless it sits where text goes
        human = vi or key in en_keys or (looked_up and re.match(r"^[A-Z]", key) is not None)
        if not human: continue
        if has_value and not explicit:
            err(path, line, f'value inside a literal ("{raw[:50]}..."): use tr("... %@", value) so the lookup sees the words alone'); continue
        if not looked_up:
            if vi or key in en_keys: err(path, line, f'"{key[:50]}" reaches the screen untranslated here: wrap it in tr("...")')
            continue
        used.add(key)
        if key not in en_keys:
            err(path, line, f'no English entry for "{key[:70]}"')

for k, v in en.items():
    if re.findall(r"%[@d]", k) != re.findall(r"%[@d]", v):
        errors.append(f"{EN_FILE}: the values in \"{k[:50]}\" and its English differ")

stale = sorted(k for k in en_keys if k not in used)
if stale:
    print(f"note: {len(stale)} English entries are not found as a plain literal (fine if built another way):")
    for k in stale[:12]: print("   ", k[:80])
    if len(stale) > 12: print(f"    ... and {len(stale) - 12} more")
if errors:
    print("\n" + "\n".join(errors))
    print(f"\n{len(errors)} problem(s) with the interface languages.")
    sys.exit(1)
print("\nstrings: every interface word has an English entry and goes through a lookup.")
EOF

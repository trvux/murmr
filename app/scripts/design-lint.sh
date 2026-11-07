#!/bin/zsh
# Fails if a view uses a visual value that is not defined in Theme.swift (see DESIGN.md).
# Run before calling any UI done:  app/scripts/design-lint.sh
cd "${0:A:h}/../Sources/MurmrStream"

typeset -a rules
rules=(
  'raw colour|Color\(red:|NSColor\(|Color\(hex'
  'named system colour|Color\.(white|black|red|green|orange|blue|gray|yellow|pink|purple|indigo)\b|[ (,]\.(white|black|red|green|orange|blue|gray|yellow|pink|purple|indigo)\b'
  'raw font (use Theme.Typeface)|\.font\(\.system\('
  'raw corner radius (use Theme.Radius)|cornerRadius: *[1-9]'
  'raw padding (use Theme.Space)|\.padding\((\.[a-zA-Z]+, *)?[1-9]'
  'raw spacing (use Theme.Space)|spacing: *[1-9]'
  'banned: gradient/purple/indigo/violet|purple|indigo|violet'
  'banned: drop shadow on content|\.shadow\('
  'banned: bounce|\.bouncy|\.bounce|interpolatingSpring'
  'banned: frosted glass|ultraThinMaterial|regularMaterial|thickMaterial|VisualEffect\('
)

found=0
for rule in $rules; do
  label=${rule%%|*}
  pattern=${rule#*|}
  # skip Theme.swift (the one place raw values live) and comment-only lines
  hits=$(grep -rnE --include='*.swift' -e "$pattern" . | grep -v '^./Theme.swift' | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//')
  if [[ -n "$hits" ]]; then
    echo "x $label"
    echo "$hits" | sed 's/^/    /' | cut -c1-150
    found=1
  fi
done

if (( found )); then
  echo "\ndesign-lint: FAILED. Move the value into Theme.swift (or use an existing token)."
  exit 1
fi
echo "design-lint: ok (no raw colours, fonts, radii or spacing outside Theme.swift)"

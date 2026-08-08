#!/bin/bash
#
# Step 1: Scan for type violations
# Finds all TypeScript files and extracts unsafe type patterns
#
# Usage: 01-scan.sh PATH
# Output: JSON to stdout
#

set -euo pipefail

TARGET_PATH="${1:-}"

if [[ -z "$TARGET_PATH" ]]; then
  echo "Usage: 01-scan.sh PATH" >&2
  exit 1
fi

# Find all TypeScript files
if [[ -f "$TARGET_PATH" ]]; then
  files=("$TARGET_PATH")
else
  mapfile -t files < <(find "$TARGET_PATH" -type f \( -name "*.ts" -o -name "*.tsx" \) ! -path "*/node_modules/*" ! -path "*/dist/*" ! -path "*/.git/*" 2>/dev/null || true)
fi

# Build JSON output
echo "{"
echo "  \"target\": \"$TARGET_PATH\","
echo "  \"files\": ["

first_file=true
for file in "${files[@]}"; do
  if [[ "$first_file" == "true" ]]; then
    first_file=false
  else
    echo ","
  fi
  printf '    "%s"' "$file"
done

echo ""
echo "  ],"
echo "  \"violations\": ["

first_violation=true

for file in "${files[@]}"; do
  [[ -f "$file" ]] || continue

  # Find violations with line numbers
  # Pattern 1: `as` assertions (excluding `as const`)
  while IFS=: read -r line_num line_content; do
    # Skip 'as const' which is safe
    if echo "$line_content" | grep -q 'as const'; then
      continue
    fi

    if [[ "$first_violation" == "true" ]]; then
      first_violation=false
    else
      echo ","
    fi

    # Escape the line content for JSON
    escaped_content=$(echo "$line_content" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr -d '\n\r')

    printf '    {"file": "%s", "line": %s, "type": "as_assertion", "content": "%s"}' "$file" "$line_num" "$escaped_content"
  done < <(grep -n ' as [A-Z]' "$file" 2>/dev/null || true)

  # Pattern 2: explicit `any` type
  while IFS=: read -r line_num line_content; do
    if [[ "$first_violation" == "true" ]]; then
      first_violation=false
    else
      echo ","
    fi

    escaped_content=$(echo "$line_content" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr -d '\n\r')

    printf '    {"file": "%s", "line": %s, "type": "any_type", "content": "%s"}' "$file" "$line_num" "$escaped_content"
  done < <(grep -nE ':\s*any\b|<any>|any\[\]' "$file" 2>/dev/null || true)

  # Pattern 3: `unknown` type (info level - may be intentional)
  while IFS=: read -r line_num line_content; do
    if [[ "$first_violation" == "true" ]]; then
      first_violation=false
    else
      echo ","
    fi

    escaped_content=$(echo "$line_content" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr -d '\n\r')

    printf '    {"file": "%s", "line": %s, "type": "unknown_type", "content": "%s"}' "$file" "$line_num" "$escaped_content"
  done < <(grep -nE ':\s*unknown\b|<unknown>' "$file" 2>/dev/null || true)

done

echo ""
echo "  ]"
echo "}"

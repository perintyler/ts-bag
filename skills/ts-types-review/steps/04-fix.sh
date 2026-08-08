#!/bin/bash
#
# Step 4: Fix violations using Claude
# Spawns Claude to automatically apply type-safe fixes
#
# Usage: 04-fix.sh ANALYSIS_FILE
# Output: JSON with fix results to stdout
#

set -euo pipefail

ANALYSIS_FILE="${1:-}"

if [[ -z "$ANALYSIS_FILE" ]]; then
  echo "Usage: 04-fix.sh ANALYSIS_FILE" >&2
  exit 1
fi

if [[ ! -f "$ANALYSIS_FILE" ]]; then
  echo "{\"fixed_count\": 0, \"error\": \"Analysis file not found: $ANALYSIS_FILE\"}"
  exit 1
fi

BARRY_CLI="${BARRY_CLI:-barry}"

# Get fixable violations
VIOLATIONS=$(jq -c '[.violations[] | select(.fixable == true)]' "$ANALYSIS_FILE")
VIOLATION_COUNT=$(echo "$VIOLATIONS" | jq 'length')

if [[ "$VIOLATION_COUNT" -eq 0 ]]; then
  echo "{\"fixed_count\": 0, \"message\": \"No fixable violations\"}"
  exit 0
fi

# Group violations by file for efficient editing
FILES=$(echo "$VIOLATIONS" | jq -r '[.[].file] | unique | .[]')

TOTAL_FIXED=0

for file in $FILES; do
  FILE_VIOLATIONS=$(echo "$VIOLATIONS" | jq -c --arg f "$file" '[.[] | select(.file == $f)]')

  # Build the prompt for this file
  PROMPT="You are a TypeScript type safety fixer. Fix the following type violations in $file.

Violations to fix:
$FILE_VIOLATIONS

Instructions:
1. Read the file at $file
2. For each violation, apply the suggested fix
3. Use proper TypeScript patterns:
   - Replace \`as Type\` with type guards or proper narrowing
   - Replace \`any\` with specific types or \`unknown\` with narrowing
   - Add type guard functions if needed
4. Ensure the code still compiles and maintains the same behavior
5. Do NOT add unnecessary type annotations - only fix the violations

After making edits, respond with ONLY valid JSON:
{
  \"file\": \"$file\",
  \"violations_fixed\": <number of violations you fixed>,
  \"changes_made\": [\"brief description of each change\"]
}

If you cannot safely fix a violation without more context, skip it and explain why."

  # Run Claude via barry CLI with edit permissions
  ALLOWED_TOOLS="Read,Edit"
  result=$("$BARRY_CLI" prompt -p "$PROMPT" -t "$ALLOWED_TOOLS" -m 15 2>&1) || true

  # Try to extract fixed count
  fixed_in_file=0
  if echo "$result" | jq -e '.violations_fixed' >/dev/null 2>&1; then
    fixed_in_file=$(echo "$result" | jq -r '.violations_fixed')
  elif json_part=$(echo "$result" | sed -n '/```json/,/```/p' | grep -v '```' | tr -d '\n') && echo "$json_part" | jq -e . >/dev/null 2>&1; then
    fixed_in_file=$(echo "$json_part" | jq -r '.violations_fixed // 0')
  fi

  TOTAL_FIXED=$((TOTAL_FIXED + fixed_in_file))
  echo "  Fixed $fixed_in_file violations in $file" >&2
done

# Output final result
echo "{\"fixed_count\": $TOTAL_FIXED, \"total_attempted\": $VIOLATION_COUNT}"

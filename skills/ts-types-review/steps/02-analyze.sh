#!/bin/bash
#
# Step 2: Analyze violations using Claude
# Spawns Claude to analyze each violation and determine severity + fix
#
# Usage: 02-analyze.sh SCAN_FILE MIN_SEVERITY
# Output: JSON to stdout
#

set -euo pipefail

SCAN_FILE="${1:-}"
MIN_SEVERITY="${2:-info}"

if [[ -z "$SCAN_FILE" ]]; then
  echo "Usage: 02-analyze.sh SCAN_FILE MIN_SEVERITY" >&2
  exit 1
fi

if [[ ! -f "$SCAN_FILE" ]]; then
  echo "{\"violations\": [], \"error\": \"Scan file not found: $SCAN_FILE\"}"
  exit 1
fi

BARRY_CLI="${BARRY_CLI:-barry}"

# Read violations from scan file
VIOLATIONS=$(jq -c '.violations' "$SCAN_FILE")
TARGET=$(jq -r '.target' "$SCAN_FILE")

# Build the prompt
PROMPT="You are a TypeScript type safety analyzer. Analyze these type violations and determine what needs to be done for safe typing.

Target: $TARGET
Violations found:
$VIOLATIONS

For each violation, analyze:
1. **Severity**:
   - 'error' for \`as any\`, explicit \`: any\` annotations (completely unsafe)
   - 'warning' for \`as Type\` assertions that may hide type errors
   - 'info' for \`unknown\` types that appear to be properly narrowed

2. **Why it's unsafe**: Brief explanation of the type safety issue

3. **Suggested fix**: Specific code change to make it type-safe
   - For \`as\` assertions: suggest type guards, generics, or proper type narrowing
   - For \`any\`: suggest the correct specific type or \`unknown\` with narrowing
   - For \`unknown\`: check if it's properly narrowed; if so, mark as acceptable

CRITICAL: Your final response must be ONLY valid JSON, nothing else:
{
  \"target\": \"$TARGET\",
  \"violations\": [
    {
      \"file\": \"path/to/file.ts\",
      \"line\": 42,
      \"type\": \"as_assertion|any_type|unknown_type\",
      \"content\": \"original line content\",
      \"severity\": \"error|warning|info\",
      \"reason\": \"Why this is unsafe\",
      \"suggested_fix\": \"Code or approach to fix it\",
      \"fixable\": true
    }
  ]
}

Only include violations with severity >= $MIN_SEVERITY (error > warning > info)."

# Run Claude via barry CLI
ALLOWED_TOOLS="Read"
result=$("$BARRY_CLI" prompt -p "$PROMPT" -t "$ALLOWED_TOOLS" -m 10 2>&1) || true

# Try to extract JSON from result
if json_part=$(echo "$result" | sed -n '/```json/,/```/p' | grep -v '```' | tr -d '\n') && echo "$json_part" | jq -e . >/dev/null 2>&1; then
  echo "$json_part"
elif echo "$result" | jq -e '.violations' >/dev/null 2>&1; then
  echo "$result"
else
  # Couldn't parse, return original violations with default severity
  jq --arg target "$TARGET" '{
    target: $target,
    violations: [.violations[] | . + {
      severity: (if .type == "any_type" then "error" elif .type == "as_assertion" then "warning" else "info" end),
      reason: "Unable to analyze - manual review needed",
      suggested_fix: "Review and add proper typing",
      fixable: false
    }]
  }' "$SCAN_FILE"
fi

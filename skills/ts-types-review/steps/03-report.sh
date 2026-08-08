#!/bin/bash
#
# Step 3: Generate markdown report
#
# Usage: 03-report.sh ANALYSIS_FILE REPORT_ID OUTPUT_FILE [FIX_MODE] [FIXED_COUNT]
# Output: Writes markdown to OUTPUT_FILE
#

set -euo pipefail

ANALYSIS_FILE="${1:-}"
REPORT_ID="${2:-}"
OUTPUT_FILE="${3:-}"
FIX_MODE="${4:-false}"
FIXED_COUNT="${5:-0}"

if [[ -z "$ANALYSIS_FILE" ]] || [[ -z "$REPORT_ID" ]] || [[ -z "$OUTPUT_FILE" ]]; then
  echo "Usage: 03-report.sh ANALYSIS_FILE REPORT_ID OUTPUT_FILE [FIX_MODE] [FIXED_COUNT]" >&2
  exit 1
fi

TARGET=$(jq -r '.target' "$ANALYSIS_FILE")
ERROR_COUNT=$(jq -r '[.violations[] | select(.severity == "error")] | length' "$ANALYSIS_FILE")
WARNING_COUNT=$(jq -r '[.violations[] | select(.severity == "warning")] | length' "$ANALYSIS_FILE")
INFO_COUNT=$(jq -r '[.violations[] | select(.severity == "info")] | length' "$ANALYSIS_FILE")
TOTAL_COUNT=$(jq -r '.violations | length' "$ANALYSIS_FILE")

cat > "$OUTPUT_FILE" << EOF
# TypeScript Type Police Report

**Report ID:** $REPORT_ID
**Target:** $TARGET
**Generated:** $(date -u +"%Y-%m-%d %H:%M:%S UTC")

## Summary

| Severity | Count |
|----------|-------|
| Errors   | $ERROR_COUNT |
| Warnings | $WARNING_COUNT |
| Info     | $INFO_COUNT |
| **Total** | **$TOTAL_COUNT** |

EOF

if [[ "$FIX_MODE" == "true" ]]; then
  cat >> "$OUTPUT_FILE" << EOF
### Fix Results

- **Fixed:** $FIXED_COUNT violations
- **Remaining:** $((TOTAL_COUNT - FIXED_COUNT)) violations

EOF
fi

# Group violations by file
cat >> "$OUTPUT_FILE" << EOF
## Violations by File

EOF

jq -r '.violations | group_by(.file) | .[] | .[0].file' "$ANALYSIS_FILE" | while read -r file; do
  echo "### \`$file\`" >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"

  jq -r --arg file "$file" '.violations[] | select(.file == $file) | "#### Line \(.line) [\(.severity | ascii_upcase)]\n\n**Type:** \(.type)\n\n```typescript\n\(.content)\n```\n\n**Issue:** \(.reason)\n\n**Fix:** \(.suggested_fix)\n\n---\n"' "$ANALYSIS_FILE" >> "$OUTPUT_FILE"
done

# Add recommendations section
cat >> "$OUTPUT_FILE" << EOF

## Recommendations

### Fixing \`as\` Assertions

Instead of:
\`\`\`typescript
const data = response.json() as MyType;
\`\`\`

Use type guards:
\`\`\`typescript
function isMyType(value: unknown): value is MyType {
  return typeof value === 'object' && value !== null && 'requiredProp' in value;
}

const data = response.json();
if (isMyType(data)) {
  // data is now MyType
}
\`\`\`

### Fixing \`any\` Types

Instead of:
\`\`\`typescript
function process(data: any) { ... }
\`\`\`

Use specific types or generics:
\`\`\`typescript
function process<T extends BaseType>(data: T) { ... }
// or
function process(data: unknown) {
  if (isExpectedType(data)) { ... }
}
\`\`\`

### When \`unknown\` is Acceptable

\`unknown\` is safe when:
- It's narrowed via type guards before use
- It's part of a catch clause (\`catch (error: unknown)\`)
- It's explicitly handled with runtime checks
EOF

echo "  Report written to: $OUTPUT_FILE"

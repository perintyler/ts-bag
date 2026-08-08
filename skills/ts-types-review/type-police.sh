#!/bin/bash
#
# TypeScript Type Police
# Main entry point - finds and analyzes unsafe type patterns
#
# Usage: type-police.sh [--min-severity=LEVEL] [--fix] PATH
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STEPS_DIR="$SCRIPT_DIR/steps"
REPORTS_DIR="$SCRIPT_DIR/.reports"

# Defaults
MIN_SEVERITY="info"
TARGET_PATH=""
FIX_MODE=false

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --min-severity=*)
      MIN_SEVERITY="${1#*=}"
      shift
      ;;
    --fix)
      FIX_MODE=true
      shift
      ;;
    --help|-h)
      cat << EOF
TypeScript Type Police - Find unsafe type patterns

Usage: type-police.sh [OPTIONS] PATH

Options:
  --min-severity=LEVEL  Minimum severity to report (error|warning|info)
  --fix                 Automatically fix violations using Claude
  --help                Show this help

Examples:
  ./type-police.sh src/index.ts           # Scan single file
  ./type-police.sh src/                   # Scan directory
  ./type-police.sh --min-severity=warning # Only warnings and errors
  ./type-police.sh --fix src/utils.ts     # Auto-fix violations

Output:
  Reports are written to: $REPORTS_DIR/
EOF
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      echo "Use --help for usage" >&2
      exit 1
      ;;
    *)
      TARGET_PATH="$1"
      shift
      ;;
  esac
done

if [[ -z "$TARGET_PATH" ]]; then
  echo "Error: PATH is required" >&2
  echo "Use --help for usage" >&2
  exit 1
fi

# Resolve path
if [[ ! -e "$TARGET_PATH" ]]; then
  echo "Error: Path not found: $TARGET_PATH" >&2
  exit 1
fi
TARGET_PATH=$(cd "$(dirname "$TARGET_PATH")" && pwd)/$(basename "$TARGET_PATH")

# Generate identifiers
TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
REPORT_ID="$TIMESTAMP"

# Create temp directory for intermediate files
WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

mkdir -p "$REPORTS_DIR"

echo "═══════════════════════════════════════════════════════════"
echo "  TypeScript Type Police"
echo "  Report ID: $REPORT_ID"
echo "  Target: $TARGET_PATH"
echo "  Min Severity: $MIN_SEVERITY"
echo "  Fix Mode: $FIX_MODE"
echo "═══════════════════════════════════════════════════════════"
echo ""

# ─────────────────────────────────────────────────────────────────
# Step 1: Scan for violations
# ─────────────────────────────────────────────────────────────────

echo "Step 1: Scanning for type violations"
echo "─────────────────────────────────────"

SCAN_FILE="$WORK_DIR/scan.json"
bash "$STEPS_DIR/01-scan.sh" "$TARGET_PATH" > "$SCAN_FILE"

# Print summary
FILE_COUNT=$(jq -r '.files | length' "$SCAN_FILE")
VIOLATION_COUNT=$(jq -r '.violations | length' "$SCAN_FILE")

echo "  Files scanned: $FILE_COUNT"
echo "  Violations found: $VIOLATION_COUNT"
echo ""

if [[ "$VIOLATION_COUNT" -eq 0 ]]; then
  echo "No type violations found."
  exit 0
fi

# ─────────────────────────────────────────────────────────────────
# Step 2: Analyze violations
# ─────────────────────────────────────────────────────────────────

echo "Step 2: Analyzing violations"
echo "────────────────────────────"

ANALYSIS_FILE="$WORK_DIR/analysis.json"
bash "$STEPS_DIR/02-analyze.sh" "$SCAN_FILE" "$MIN_SEVERITY" > "$ANALYSIS_FILE"

# Print summary by severity
ERROR_COUNT=$(jq -r '[.violations[] | select(.severity == "error")] | length' "$ANALYSIS_FILE")
WARNING_COUNT=$(jq -r '[.violations[] | select(.severity == "warning")] | length' "$ANALYSIS_FILE")
INFO_COUNT=$(jq -r '[.violations[] | select(.severity == "info")] | length' "$ANALYSIS_FILE")

echo "  Errors: $ERROR_COUNT"
echo "  Warnings: $WARNING_COUNT"
echo "  Info: $INFO_COUNT"
echo ""

# ─────────────────────────────────────────────────────────────────
# Step 3: Fix (if requested)
# ─────────────────────────────────────────────────────────────────

FIXED_COUNT=0
if [[ "$FIX_MODE" == "true" ]]; then
  echo "Step 3: Fixing violations"
  echo "─────────────────────────"

  FIX_RESULT="$WORK_DIR/fix-result.json"
  bash "$STEPS_DIR/04-fix.sh" "$ANALYSIS_FILE" > "$FIX_RESULT"

  FIXED_COUNT=$(jq -r '.fixed_count' "$FIX_RESULT")
  echo "  Fixed: $FIXED_COUNT violations"
  echo ""
fi

# ─────────────────────────────────────────────────────────────────
# Step 4: Generate Report
# ─────────────────────────────────────────────────────────────────

STEP_NUM=$([[ "$FIX_MODE" == "true" ]] && echo "4" || echo "3")
echo "Step $STEP_NUM: Generating Report"
echo "─────────────────────────────────"

REPORT_FILE="$REPORTS_DIR/report-$REPORT_ID.md"
bash "$STEPS_DIR/03-report.sh" "$ANALYSIS_FILE" "$REPORT_ID" "$REPORT_FILE" "$FIX_MODE" "$FIXED_COUNT"

echo ""

# ─────────────────────────────────────────────────────────────────
# Final Summary
# ─────────────────────────────────────────────────────────────────

REMAINING_ERRORS=$((ERROR_COUNT - FIXED_COUNT))
[[ $REMAINING_ERRORS -lt 0 ]] && REMAINING_ERRORS=0

if [[ "$REMAINING_ERRORS" -gt 0 ]]; then
  VERDICT="FAIL"
  VERDICT_EMOJI="❌"
elif [[ "$WARNING_COUNT" -gt 0 ]]; then
  VERDICT="WARN"
  VERDICT_EMOJI="⚠️"
else
  VERDICT="PASS"
  VERDICT_EMOJI="✅"
fi

echo "═══════════════════════════════════════════════════════════"
echo "  $VERDICT_EMOJI Verdict: $VERDICT"
if [[ "$FIX_MODE" == "true" ]]; then
  echo "  Fixed: $FIXED_COUNT | Remaining: $ERROR_COUNT errors, $WARNING_COUNT warnings"
else
  echo "  $ERROR_COUNT errors, $WARNING_COUNT warnings, $INFO_COUNT info"
fi
echo ""
echo "  Report: $REPORT_FILE"
echo "═══════════════════════════════════════════════════════════"

# Exit code based on remaining errors
[[ "$REMAINING_ERRORS" -eq 0 ]] && exit 0 || exit 1

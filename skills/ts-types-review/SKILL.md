---
name: ts-types-review
description: >
  Find and fix unsafe TypeScript type patterns — `as` assertions, `any` types, `unknown` without narrowing.
  Use when asked to "check types", "find type issues", "type audit", or "fix unsafe types".
allowed-tools: Bash, Read, Edit, Grep, Glob
args:
  - name: path
    description: File or directory to scan
    required: true
  - name: fix
    description: Auto-fix violations using Claude (flag, no value)
    required: false
  - name: min-severity
    description: Minimum severity to report (error|warning|info, default info)
    required: false
---

# TypeScript Types Review

Finds and optionally auto-fixes unsafe TypeScript type patterns in a codebase.

## How to Run

The pipeline lives at the skill's directory. Determine the skill directory from this file's location, then run:

```bash
# Scan a file or directory
bash <skill-dir>/type-police.sh src/

# Scan with severity filter
bash <skill-dir>/type-police.sh --min-severity=warning src/

# Auto-fix violations
bash <skill-dir>/type-police.sh --fix src/
```

## What It Finds

| Pattern | Default Severity | Rationale |
|---------|-----------------|-----------|
| `as any` | error | Completely bypasses type system |
| `: any` | error | Explicit any annotation |
| `as Type` (non-const) | warning | May hide type errors |
| `: unknown` | info | Safe if properly narrowed |

## Pipeline

```
01-scan.sh      ->  Find files, extract type violations (bash, fast)
       |
02-analyze.sh   ->  Analyze each violation via Claude (spawns agent)
       |
03-report.sh    ->  Generate markdown report
       |
04-fix.sh       ->  Auto-fix violations via Claude (optional, with --fix)
```

## Fix Patterns Applied

- `as Type` -> type guards with `value is Type`
- `any` -> specific types or `unknown` with narrowing
- Adds type guard functions where needed

## When the User Asks to Check Types

1. If they specify a file/directory, pass it as the target
2. If they want auto-fix, add `--fix`
3. If they only want errors, add `--min-severity=error`
4. After running, summarize the results and link to the report

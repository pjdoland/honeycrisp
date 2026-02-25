# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Honeycrisp is a single-file, read-only Mac disk audit tool (`honeycrisp.sh`). It scans for common space consumers (caches, logs, old downloads, developer tool artifacts, etc.) and reports findings with sizes and safety ratings. It never deletes, moves, or modifies any file.

## Key Constraints

- **Pure bash, no external dependencies** — must work with macOS's built-in bash 3.x (no associative arrays, no `declare -A`, no bash 4+ features)
- **No destructive commands** — `rm`, `rmdir`, `mv`, `trash`, `unlink` must never appear as executed commands (only allowed in instructional echo strings telling the user what they *could* run)
- **No sudo required** — the script runs unprivileged; note where sudo would help but don't require it
- **No network requests, no file writes** (except optional `--output` tee), no package installs
- **Graceful degradation** — missing paths, permission errors, and absent tools (Xcode, Docker, brew) must be handled silently without aborting

## Validation

```bash
# Syntax check
bash -n honeycrisp.sh

# Quick test run (skips slow deep scans)
./honeycrisp.sh --quick

# Full scan
./honeycrisp.sh
```

There is no test suite, linter, or build step. Validation is syntax checking and manual test runs.

## Architecture

Everything lives in `honeycrisp.sh`. The structure follows a linear scan pattern:

1. **Argument parsing & setup** — flags, color init, tee for `--output`
2. **Helper functions** — `safe_du_bytes()`, `format_size()`, `print_row()`, `add_summary()`, etc.
3. **Category scan sections** — each prints its own header, scans paths, calls `add_summary()` to register totals
4. **Summary table** — iterates `SUMMARY_CATS`/`SUMMARY_SIZES`/`SUMMARY_SAFETY_LABELS` parallel arrays (not associative arrays) sorted by size descending
5. **Next steps guide** — static instructional text per category

To add a new scan category: add a new section between the category scans and the summary table, call `add_summary "Category Name" "$bytes" "🟢 Safe"` to register it, and add a corresponding entry in the next steps section.

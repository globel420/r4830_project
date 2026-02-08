#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./tree_list.sh [FOLDER] [OUTPUT_FILE]
# Defaults:
#   FOLDER = current directory
#   OUTPUT_FILE = file_tree.txt

ROOT="${1:-.}"
OUT="${2:-file_tree.txt}"

if [[ ! -d "$ROOT" ]]; then
  echo "ERROR: Folder not found: $ROOT" >&2
  exit 1
fi

# Make paths nice (absolute root, relative listing)
ABS_ROOT="$(cd "$ROOT" && pwd)"

{
  echo "FILE TREE"
  echo "Root: $ABS_ROOT"
  echo "Generated: $(date)"
  echo

  # Prefer `tree` if installed; otherwise use `find`
  if command -v tree >/dev/null 2>&1; then
    # -a: include dotfiles, -f: full paths, --noreport: no summary
    (cd "$ABS_ROOT" && tree -a -f --noreport .)
  else
    echo "(tree command not found; using find)"
    echo
    (cd "$ABS_ROOT" && find . -print | LC_ALL=C sort)
  fi
} > "$OUT"

echo "Wrote: $OUT"

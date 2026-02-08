#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
OUTDIR="${2:-_filemap}"
mkdir -p "$OUTDIR"

# Exclusions (add more if you want)
EXCLUDE_DIRS=(
  ".git"
  ".DS_Store"
  "node_modules"
  ".next"
  "dist"
  "build"
  "__pycache__"
  ".venv"
  ".pytest_cache"
  ".mypy_cache"
)

# Build prune expression for find
PRUNE_EXPR=()
for d in "${EXCLUDE_DIRS[@]}"; do
  PRUNE_EXPR+=( -name "$d" -o )
done
# remove trailing -o
unset 'PRUNE_EXPR[${#PRUNE_EXPR[@]}-1]'

TXT="$OUTDIR/file_map.txt"
CSV="$OUTDIR/file_map.csv"
SUM="$OUTDIR/file_map_summary.txt"

echo "ROOT: $(cd "$ROOT" && pwd)" > "$SUM"
echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$SUM"
echo "" >> "$SUM"

# TXT: directory tree (portable-ish)
{
  echo "=== FILE TREE (excluding: ${EXCLUDE_DIRS[*]}) ==="
  echo ""
  # Prefer 'tree' if installed, else fallback
  if command -v tree >/dev/null 2>&1; then
    tree -a -I "$(IFS='|'; echo "${EXCLUDE_DIRS[*]}")" "$ROOT"
  else
    # Fallback: print dirs then files
    echo "[tree not installed] Using find fallback"
    find "$ROOT" \( -type d \( "${PRUNE_EXPR[@]}" \) -prune \) -o -print \
      | sed "s|^$ROOT|.|" \
      | sort
  fi
} > "$TXT"

# CSV: path,type,size_bytes,mtime
echo "path,type,size_bytes,mtime_iso" > "$CSV"
find "$ROOT" \( -type d \( "${PRUNE_EXPR[@]}" \) -prune \) -o -print0 \
| while IFS= read -r -d '' p; do
    rel="${p#$ROOT/}"
    [[ "$p" == "$ROOT" ]] && rel="."
    if [[ -d "$p" ]]; then
      type="dir"
      size=0
    else
      type="file"
      # macOS stat
      size="$(stat -f%z "$p" 2>/dev/null || echo 0)"
    fi
    # mtime ISO (macOS)
    mtime="$(stat -f%Sm -t "%Y-%m-%dT%H:%M:%S%z" "$p" 2>/dev/null || echo "")"
    # CSV-escape quotes
    rel_esc="${rel//\"/\"\"}"
    echo "\"$rel_esc\",\"$type\",\"$size\",\"$mtime\""
  done >> "$CSV"

# Summary stats
FILE_COUNT="$(awk -F',' 'NR>1 && $2 ~ /file/ {c++} END{print c+0}' "$CSV")"
DIR_COUNT="$(awk -F',' 'NR>1 && $2 ~ /dir/ {c++} END{print c+0}' "$CSV")"
TOTAL_BYTES="$(awk -F',' 'NR>1 && $2 ~ /file/ {gsub(/"/,"",$3); s+=$3} END{printf "%.0f", s+0}' "$CSV")"

{
  echo "Dirs:  $DIR_COUNT"
  echo "Files: $FILE_COUNT"
  echo "Bytes: $TOTAL_BYTES"
  echo ""
  echo "Wrote:"
  echo "  $TXT"
  echo "  $CSV"
  echo "  $SUM"
} >> "$SUM"

echo "OK -> $OUTDIR (file_map.txt, file_map.csv, file_map_summary.txt)"

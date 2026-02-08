#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./map_files.sh [ROOT_DIR] [OUT_DIR]
# Defaults:
#   ROOT_DIR = .
#   OUT_DIR  = ./_filemap

ROOT="${1:-.}"
OUTDIR="${2:-./_filemap}"

if [[ ! -d "$ROOT" ]]; then
  echo "ERROR: Root folder not found: $ROOT" >&2
  exit 1
fi

ABS_ROOT="$(cd "$ROOT" && pwd)"
mkdir -p "$OUTDIR"

CSV="$OUTDIR/file_map.csv"
TXT="$OUTDIR/file_map.txt"
SUM="$OUTDIR/file_map_summary.txt"

# CSV header
echo "type,size_bytes,mtime_iso,rel_path,abs_path" > "$CSV"

# Build CSV using find + stat (macOS compatible)
# type: f(file) or d(dir)
while IFS= read -r -d '' p; do
  rel="${p#"$ABS_ROOT"/}"
  # For the root itself, rel becomes the absolute path; normalize
  [[ "$p" == "$ABS_ROOT" ]] && rel="."
  t="d"
  [[ -f "$p" ]] && t="f"

  # macOS stat:
  # %z = size bytes (0 for dirs often)
  # %Sm = formatted mtime
  size="$(stat -f '%z' "$p" 2>/dev/null || echo 0)"
  mtime="$(stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%S%z' "$p" 2>/dev/null || echo "")"

  # CSV escape quotes
  esc_rel="${rel//\"/\"\"}"
  esc_abs="${p//\"/\"\"}"

  echo "$t,$size,$mtime,\"$esc_rel\",\"$esc_abs\"" >> "$CSV"
done < <(find "$ABS_ROOT" -print0)

# Human-readable folder grouping (directories first, then files)
{
  echo "FILE/FOLDER MAP"
  echo "Root: $ABS_ROOT"
  echo "Generated: $(date)"
  echo

  # List directories
  echo "=== DIRECTORIES ==="
  find "$ABS_ROOT" -type d -print | sed "s|^$ABS_ROOT|.|" | LC_ALL=C sort
  echo

  echo "=== FILES (grouped by folder) ==="
  # Group files by directory
  find "$ABS_ROOT" -type f -print | sed "s|^$ABS_ROOT/||" | LC_ALL=C sort \
    | awk -F/ '
      {
        dir="."
        if (NF>1) {
          dir=$1
          for(i=2;i<NF;i++) dir=dir"/"$i
        }
        file=$NF
        if (dir!=lastdir) {
          if (NR>1) print ""
          print "[" dir "]"
          lastdir=dir
        }
        print "  - " file
      }'
} > "$TXT"

# Summary: counts + top 30 largest files
{
  echo "SUMMARY"
  echo "Root: $ABS_ROOT"
  echo "Generated: $(date)"
  echo

  dir_count="$(find "$ABS_ROOT" -type d | wc -l | tr -d ' ')"
  file_count="$(find "$ABS_ROOT" -type f | wc -l | tr -d ' ')"
  echo "Directories: $dir_count"
  echo "Files:       $file_count"
  echo

  echo "Top 30 largest files:"
  # size<TAB>path, then sort numeric desc
  find "$ABS_ROOT" -type f -print0 \
    | xargs -0 stat -f '%z	%N' \
    | sort -nr \
    | head -n 30 \
    | awk -v root="$ABS_ROOT/" '
        BEGIN { OFS=""; }
        {
          size=$1; $1=""; sub(/^ /,"")
          path=$0
          rel=path
          sub(root,"",rel)
          printf "%12d  %s\n", size, rel
        }'
  echo

  echo "Output files:"
  echo " - $CSV"
  echo " - $TXT"
  echo " - $SUM"
} > "$SUM"

echo "Done."
echo "Wrote:"
echo "  $CSV"
echo "  $TXT"
echo "  $SUM"

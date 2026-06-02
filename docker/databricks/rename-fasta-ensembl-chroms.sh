#!/usr/bin/env bash
# Rename UCSC-style FASTA headers (>chr1) to Ensembl GFF3 style (>1, >MT).
# Streaming — safe for multi-GB FASTA. Does not modify the input file.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
export FASTVEP_REFERENCE_DIR="${FASTVEP_REFERENCE_DIR:-$ROOT/reference}"
set -a
# shellcheck disable=SC1091
source "$ROOT/.env"
set +a

IN="${1:-$FASTA}"
OUT="${2:-${IN%.fa}.new.fa}"

[[ -f "$IN" ]] || { echo "Missing input FASTA: $IN" >&2; exit 1; }

echo "Input:  $IN"
echo "Output: $OUT"
echo "Renaming contigs (>chrN -> >N, >chrM -> >MT)..."

awk '
/^>/ {
  name = substr($0, 2)
  split(name, parts, " ")
  name = parts[1]
  if (name == "chrM") {
    print ">MT"
    next
  }
  if (substr(name, 1, 3) == "chr") {
    print ">" substr(name, 4)
    next
  }
  print $0
  next
}
{ print }
' "$IN" > "$OUT"

if [[ ! -s "$OUT" ]]; then
  echo "ERROR: output FASTA missing or empty: $OUT" >&2
  exit 1
fi

echo "Indexing with samtools faidx..."
if command -v samtools >/dev/null 2>&1; then
  samtools faidx "$OUT"
else
  echo "samtools not in PATH — run: samtools faidx $OUT" >&2
  exit 1
fi

echo "Done. First contigs:"
head -5 "${OUT}.fai"
du -h "$OUT"

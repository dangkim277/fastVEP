#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
export FASTVEP_REFERENCE_DIR="$ROOT/reference"
set -a
# shellcheck disable=SC1091
source "$ROOT/.env"
set +a

FASTVEP="${FASTVEP:-fastvep}"
[[ -x "$ROOT/fastvep" ]] && FASTVEP="$ROOT/fastvep"

for f in "$GFF3_ENSEMBL" "$GFF3_REFSEQ" "$FASTA" "$FASTA_FAI"; do
    [[ -f "$f" ]] || { echo "Missing $f — update .env and reference/" >&2; exit 1; }
done

echo "Building merged cache for ${FASTVEP_REF_RELEASE}..."
echo "  Ensembl: $GFF3_ENSEMBL"
echo "  RefSeq:  $GFF3_REFSEQ"
echo "  FASTA:   $FASTA"
echo "  Output:  $TRANSCRIPT_CACHE"

"$FASTVEP" cache \
    --gff3 "$GFF3_ENSEMBL" \
    --gff3 "$GFF3_REFSEQ" \
    --fasta "$FASTA" \
    --output "$TRANSCRIPT_CACHE"

du -h "$TRANSCRIPT_CACHE"

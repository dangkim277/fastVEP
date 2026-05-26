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

for f in "$GFF3" "$FASTA" "${FASTA}.fai"; do
    [[ -f "$f" ]] || { echo "Missing $f — update .env and reference/" >&2; exit 1; }
done

echo "Building cache for ${FASTVEP_REF_RELEASE}..."
"$FASTVEP" cache --gff3 "$GFF3" --fasta "$FASTA" --output "$TRANSCRIPT_CACHE"
du -h "$TRANSCRIPT_CACHE"

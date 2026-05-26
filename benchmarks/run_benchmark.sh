#!/usr/bin/env bash
#
# fastVEP Multi-Organism Benchmark Suite
#
# Benchmarks fastVEP annotation performance across model organisms using
# real Ensembl annotations and gold-standard variant call sets.
#
# Data sources:
#   Yeast       — 260K Ensembl/SGD variants (R64), Ensembl 115
#   Drosophila  — 4.4M DGRP2 variants (BDGP6), Ensembl 115
#   Arabidopsis — 12.9M 1001 Genomes variants (TAIR10), Ensembl 115
#   Mouse       — 1M Ensembl/EVA variants (GRCm39), Ensembl 115
#   Human       — 4.05M GIAB HG002 variants (GRCh38), Ensembl 115
#
# Prerequisites:
#   ./download_data.sh --all
#
# Each benchmark: 3 runs, median reported, with binary transcript cache.
#
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FASTVEP="$PROJECT_DIR/target/release/fastvep"
OUTPUT_DIR="$SCRIPT_DIR/output"
LOG_DIR="$OUTPUT_DIR/logs"
TEST_DATA="$PROJECT_DIR/test_data"
ORG_DATA="$TEST_DATA/organisms"
VCF_DATA="$TEST_DATA/benchmark_vcfs"
RUNS=3

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

on_error() {
    local exit_code="$?"
    local line="${1:-unknown}"
    local command="${2:-unknown}"
    mkdir -p "$LOG_DIR"
    {
        echo ""
        echo "== $(date '+%Y-%m-%d %H:%M:%S') benchmark script error =="
        echo "exit_code: $exit_code"
        echo "line:      $line"
        echo "command:   $command"
    } >> "$LOG_DIR/run_benchmark.error.log"
    echo -e "\n${RED}ERROR:${NC} benchmark script failed at line $line" >&2
    echo -e "${YELLOW}Command:${NC} $command" >&2
    echo -e "${YELLOW}Log:${NC} $LOG_DIR/run_benchmark.error.log" >&2
    exit "$exit_code"
}

trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

print_header() {
    echo ""
    echo -e "${BOLD}============================================================${NC}"
    echo -e "${BOLD}  fastVEP Multi-Organism Benchmark Suite${NC}"
    echo -e "${BOLD}============================================================${NC}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${CYAN}--- $1 ---${NC}"
}

build_release() {
    print_section "Building fastVEP (release mode with LTO)"
    cd "$PROJECT_DIR"
    cargo build --release 2>&1 | tail -1
    if [ ! -f "$FASTVEP" ]; then
        echo -e "${RED}ERROR: Build failed.${NC}"
        exit 1
    fi
    echo -e "${GREEN}Build successful.${NC}"
}

count_variants() {
    awk 'BEGIN { n = 0 } !/^#/ { n++ } END { print n }' "$1"
}

now_ns() {
    date +%s%N
}

elapsed_seconds() {
    local start="$1" end="$2"
    awk -v start="$start" -v end="$end" 'BEGIN { printf "%.4f", (end - start) / 1000000000 }'
}

time_run() {
    local input_vcf="$1"
    local gff3="$2"
    local fmt="$3"
    local outfile="$4"
    local fasta="${5:-}"
    local log_file="$LOG_DIR/$(basename "$outfile").log"

    local fasta_args=()
    if [[ -n "$fasta" && -f "$fasta" ]]; then
        fasta_args=(--fasta "$fasta")
    fi

    local start end
    mkdir -p "$LOG_DIR"
    {
        echo ""
        echo "== $(date '+%Y-%m-%d %H:%M:%S') annotate $(basename "$input_vcf") =="
        echo "input:  $input_vcf"
        echo "gff3:   $gff3"
        echo "fasta:  ${fasta:-none}"
        echo "output: $outfile"
    } >> "$log_file"

    start=$(now_ns)
    if ! "$FASTVEP" annotate \
        --input "$input_vcf" \
        --gff3 "$gff3" \
        "${fasta_args[@]}" \
        --output "$outfile" \
        --output-format "$fmt" \
        --hgvs \
        >> "$log_file" 2>&1; then
        echo -e "\n${RED}ERROR:${NC} fastVEP annotate failed for $(basename "$input_vcf")" >&2
        echo -e "${YELLOW}Log:${NC} $log_file" >&2
        echo -e "${YELLOW}Last 40 log lines:${NC}" >&2
        tail -n 40 "$log_file" >&2
        return 1
    fi
    end=$(now_ns)

    elapsed_seconds "$start" "$end"
}

median_time() {
    local n="$1"
    shift
    local times=()
    for ((r=1; r<=n; r++)); do
        local elapsed
        if ! elapsed="$(time_run "$@")"; then
            return 1
        fi
        times+=( "$elapsed" )
    done
    printf '%s\n' "${times[@]}" | sort -n | awk '
        { vals[NR] = $1 }
        END {
            if (NR == 0) exit 1
            mid = int(NR / 2) + 1
            printf "%.4f", vals[mid]
        }
    '
}

warm_cache() {
    local gff3="$1"
    local fasta="${2:-}"
    local cache_file

    if [[ "$gff3" == *.gz ]]; then
        cache_file="${gff3%.gz}.fastvep.cache"
    else
        cache_file="${gff3}.fastvep.cache"
    fi

    if [[ -f "$cache_file" ]]; then
        echo -e "  Cache exists: $(basename $cache_file)"
        return 0
    fi

    echo -e "  ${YELLOW}Building cache for $(basename $gff3)...${NC}"
    local tmp_vcf
    tmp_vcf=$(mktemp /tmp/fastvep_warm_XXXXXX.vcf)
    local chrom
    chrom=$(grep -m1 -v '^#' "$gff3" | cut -f1)
    printf '##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n%s\t1\t.\tA\tG\t.\tPASS\t.\n' "$chrom" > "$tmp_vcf"

    local fasta_args=""
    if [[ -n "$fasta" && -f "$fasta" ]]; then
        fasta_args="--fasta $fasta"
    fi

    mkdir -p "$LOG_DIR"
    local log_file="$LOG_DIR/warm_cache_$(basename "$gff3").log"
    if ! "$FASTVEP" annotate --input "$tmp_vcf" --gff3 "$gff3" $fasta_args \
        --output /dev/null --output-format tab > "$log_file" 2>&1; then
        echo -e "  ${RED}Cache warmup failed:${NC} $(basename "$gff3")" >&2
        echo -e "  ${YELLOW}Log:${NC} $log_file" >&2
        tail -n 40 "$log_file" >&2
    fi
    rm -f "$tmp_vcf"

    if [[ -f "$cache_file" ]]; then
        echo -e "  ${GREEN}Cache built: $(basename $cache_file)${NC}"
    else
        echo -e "  ${RED}Warning: cache not created${NC}"
    fi
}

# ═══════════════════════════════════════════════════════════════
# Register benchmarks
# ═══════════════════════════════════════════════════════════════

declare -a ALL_NAMES=()
declare -a ALL_VCFS=()
declare -a ALL_GFF3S=()
declare -a ALL_FASTAS=()
declare -a ALL_ORGANISMS=()

add_benchmark() {
    local name="$1" vcf="$2" gff3="$3" fasta="${4:-}" organism="$5"
    if [[ ! -f "$vcf" ]]; then
        echo -e "  ${YELLOW}Skipping $name: $(basename "$vcf") not found${NC}"
        return 0
    fi
    if [[ ! -f "$gff3" ]]; then
        echo -e "  ${YELLOW}Skipping $name: $(basename "$gff3") not found${NC}"
        return 0
    fi
    ALL_NAMES+=("$name")
    ALL_VCFS+=("$vcf")
    ALL_GFF3S+=("$gff3")
    ALL_FASTAS+=("$fasta")
    ALL_ORGANISMS+=("$organism")
}

run_benchmarks() {
    mkdir -p "$OUTPUT_DIR" "$LOG_DIR"

    # # ── Yeast (R64) ──
    # if [[ -f "$ORG_DATA/yeast.gff3" ]]; then
    #     print_section "Pre-warming: Yeast (R64)"
    #     warm_cache "$ORG_DATA/yeast.gff3" "$ORG_DATA/yeast.fa"
    #     add_benchmark "yeast_100k" "$VCF_DATA/yeast_100k.vcf" "$ORG_DATA/yeast.gff3" "$ORG_DATA/yeast.fa" "Yeast"
    # fi

    # # # ── Mouse (GRCm39) ──
    # # if [[ -f "$ORG_DATA/mouse.gff3" ]]; then
    # #     print_section "Pre-warming: Mouse (GRCm39)"
    # #     warm_cache "$ORG_DATA/mouse.gff3" "$ORG_DATA/mouse.fa"
    # #     add_benchmark "mouse_100k" "$VCF_DATA/mouse_100k.vcf" "$ORG_DATA/mouse.gff3" "$ORG_DATA/mouse.fa" "Mouse"
    # #     add_benchmark "mouse_500k" "$VCF_DATA/mouse_500k.vcf" "$ORG_DATA/mouse.gff3" "$ORG_DATA/mouse.fa" "Mouse"
    # # fi

    # ── Human (GRCh38, GIAB HG002) ──
    local HUMAN_GFF3="$TEST_DATA/Homo_sapiens.GRCh38.115.gff3"
    local HUMAN_FA="$TEST_DATA/Homo_sapiens.GRCh38.dna.primary_assembly.fa"
    [[ -f "$HUMAN_GFF3" ]] || HUMAN_GFF3="$ORG_DATA/human/Homo_sapiens.GRCh38.115.gff3"
    [[ -f "$HUMAN_FA" ]] || HUMAN_FA="$ORG_DATA/human/Homo_sapiens.GRCh38.dna.primary_assembly.fa"
    if [[ -f "$HUMAN_GFF3" ]]; then
        print_section "Pre-warming: Human full genome (GRCh38)"
        warm_cache "$HUMAN_GFF3" "$HUMAN_FA"
        add_benchmark "COLO829v003T.sage.somatic" "$VCF_DATA/COLO829v003T.sage.somatic.vcf" "$HUMAN_GFF3" "$HUMAN_FA" "Sage Somantic"
    fi

    # # ── Arabidopsis (TAIR10) ──
    # if [[ -f "$ORG_DATA/arabidopsis.gff3" ]]; then
    #     print_section "Pre-warming: Arabidopsis (TAIR10)"
    #     warm_cache "$ORG_DATA/arabidopsis.gff3" "$ORG_DATA/arabidopsis.fa"
    #     add_benchmark "arabidopsis_ensembl" "$VCF_DATA/arabidopsis_ensembl_full.vcf" "$ORG_DATA/arabidopsis.gff3" "$ORG_DATA/arabidopsis.fa" "Arabidopsis"
    # fi

    # ═══════════════════════════════════════════════════════════════
    # RUN ALL BENCHMARKS
    # ═══════════════════════════════════════════════════════════════
    if [[ ${#ALL_NAMES[@]} -eq 0 ]]; then
        echo -e "\n${RED}No benchmark data found. Run ./download_data.sh --all first.${NC}"
        exit 1
    fi

    print_section "Running benchmarks (median of $RUNS runs each)"

    declare -A RESULTS

    for i in "${!ALL_NAMES[@]}"; do
        local name="${ALL_NAMES[$i]}"
        local vcf="${ALL_VCFS[$i]}"
        local gff="${ALL_GFF3S[$i]}"
        local fasta="${ALL_FASTAS[$i]:-}"
        local organism="${ALL_ORGANISMS[$i]}"
        local nvar
        if ! nvar=$(count_variants "$vcf" 2>"$LOG_DIR/${name}.count.log"); then
            echo -e "${RED}ERROR:${NC} failed to count variants for $name" >&2
            echo -e "${YELLOW}VCF:${NC} $vcf" >&2
            echo -e "${YELLOW}Log:${NC} $LOG_DIR/${name}.count.log" >&2
            tail -n 40 "$LOG_DIR/${name}.count.log" >&2
            return 1
        fi
        if [[ "$nvar" -eq 0 ]]; then
            echo -e "  ${YELLOW}Skipping $name: no variant records in $(basename "$vcf")${NC}"
            continue
        fi

        printf "  %-25s (%8s variants, %-12s) ... " "$name" "$nvar" "$organism"
        local elapsed
        if ! elapsed=$(median_time "$RUNS" "$vcf" "$gff" "vcf" "$OUTPUT_DIR/${name}.annotated.vcf" "$fasta"); then
            echo -e "${RED}failed${NC}"
            echo -e "${YELLOW}See logs:${NC} $LOG_DIR/"
            return 1
        fi

        local vps
        vps=$(awk -v elapsed="$elapsed" -v nvar="$nvar" 'BEGIN {
            if (elapsed > 0) {
                printf "%.0f", nvar / elapsed
            } else {
                printf "inf"
            }
        }')
        printf "${GREEN}%8s sec${NC}  (%s v/s)\n" "$elapsed" "$vps"
        RESULTS["${name}"]="${elapsed} ${nvar} ${vps} ${organism}"
    done

    # ═══════════════════════════════════════════════════════════════
    # SUMMARY TABLE
    # ═══════════════════════════════════════════════════════════════
    echo ""
    echo -e "${BOLD}============================================================${NC}"
    echo -e "${BOLD}  Benchmark Summary (median of ${RUNS} runs, VCF output)${NC}"
    echo -e "${BOLD}============================================================${NC}"
    echo ""
    printf "${BOLD}%-25s %-12s %10s %10s %15s${NC}\n" "Dataset" "Organism" "Variants" "Time (s)" "Variants/sec"
    printf "%-25s %-12s %10s %10s %15s\n" "-------------------------" "------------" "----------" "----------" "---------------"

    for name in "${ALL_NAMES[@]}"; do
        if [ -n "${RESULTS[$name]+x}" ]; then
            local parts=(${RESULTS[$name]})
            printf "%-25s %-12s %10s %10s %15s\n" "$name" "${parts[3]}" "${parts[1]}" "${parts[0]}" "${parts[2]}"
        fi
    done

    # ═══════════════════════════════════════════════════════════════
    # CSV OUTPUT
    # ═══════════════════════════════════════════════════════════════
    local csv_file="$OUTPUT_DIR/benchmark_results.csv"
    echo "dataset,organism,variants,time_seconds,variants_per_second" > "$csv_file"
    for name in "${ALL_NAMES[@]}"; do
        if [ -n "${RESULTS[$name]+x}" ]; then
            local parts=(${RESULTS[$name]})
            echo "${name},${parts[3]},${parts[1]},${parts[0]},${parts[2]}" >> "$csv_file"
        fi
    done

    echo ""
    echo -e "${GREEN}CSV results:${NC} $csv_file"
    echo -e "${BOLD}Output files:${NC} $OUTPUT_DIR/"
}

# ═══════════════════════════════════════════════════════════════
# ENTRY POINT
# ═══════════════════════════════════════════════════════════════
print_header

echo "Date:     $(date '+%Y-%m-%d %H:%M:%S')"
echo "System:   $(uname -s) $(uname -m)"
echo "Rust:     $(rustc --version 2>/dev/null || echo 'not found')"
echo "Runs:     $RUNS per benchmark (median reported)"
echo "Data:     $VCF_DATA/"
echo ""

build_release
run_benchmarks

echo ""
echo -e "${GREEN}Benchmark complete.${NC}"

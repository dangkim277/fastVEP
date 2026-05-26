# fastVEP Databricks Docker image

Single image for Databricks: **Glow** + **fastVEP** + **GRCh38 reference** + **`fastvep-annotate`** wrapper.

**Edit `.env` only** when changing release or paths. Bash expands `${}` when the file is sourced.

```bash
FASTVEP_REF_RELEASE=grch38-r115
FASTVEP_REFERENCE_DIR=${FASTVEP_REFERENCE_DIR:-/opt/fastvep/reference}
GFF3=${FASTVEP_REFERENCE_DIR}/Homo_sapiens.GRCh38.115.gff3
FASTA=${FASTVEP_REFERENCE_DIR}/Homo_sapiens.GRCh38.dna.primary_assembly.fa
TRANSCRIPT_CACHE=${FASTVEP_REFERENCE_DIR}/Homo_sapiens.GRCh38.115.gff3.fastvep.cache
FASTVEP_HGVS=1
```

Docker tag should match `FASTVEP_REF_RELEASE` (e.g. `grch38-r115`).

| Consumer | How |
|----------|-----|
| `Dockerfile` | `RUN set -a && . /opt/fastvep/.env && set +a` |
| `fastvep-annotate` | `source /opt/fastvep/.env` |
| `build-reference-cache.sh` | `export FASTVEP_REFERENCE_DIR=./reference` then `source .env` |

**Runtime override (no rebuild):** `FASTVEP_GFF3`, `FASTVEP_FASTA`, `TRANSCRIPT_CACHE` / `FASTVEP_TRANSCRIPT_CACHE`, or `FASTVEP_ENV_FILE=/dbfs/.../.env`.

---

## 1. Layout before build

```text
docker/databricks/
  .env
  Dockerfile
  fastvep-annotate
  fastvep                    # Linux binary (not fastvep.exe)
  reference/
    Homo_sapiens.GRCh38.115.gff3
    Homo_sapiens.GRCh38.dna.primary_assembly.fa
    Homo_sapiens.GRCh38.dna.primary_assembly.fa.fai
    Homo_sapiens.GRCh38.115.gff3.fastvep.cache
```

---

## 2. Build (local)

### Step A — Linux `fastvep` binary

On Linux:

```bash
cargo build --release --package fastvep-cli
cp target/release/fastvep docker/databricks/fastvep
```

On Windows (build inside Docker, from repo root):

```powershell
docker run --rm `
  -v "C:\Users\DangKim\Workspace\fastVEP:/work" `
  -w /work `
  rust:latest `
  bash -lc 'export PATH=/usr/local/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; apt-get update -qq && apt-get install -y -qq build-essential pkg-config ca-certificates; cargo build --release --package fastvep-cli --target-dir /work/target-linux; cp /work/target-linux/release/fastvep /work/docker/databricks/fastvep'
```

### Step B — Reference files

Copy GFF3 + FASTA into `docker/databricks/reference/` (names must match `.env`), then:

```bash
samtools faidx docker/databricks/reference/Homo_sapiens.GRCh38.dna.primary_assembly.fa
```

### Step C — Transcript cache (on host, not in Dockerfile)

```bash
cd docker/databricks
./build-reference-cache.sh
```

### Step D — Docker image

Build from **`docker/databricks`** (so `COPY reference/` works):

```bash
cd docker/databricks
docker build --platform linux/amd64 -t fastvep:grch38-r115 .
```

Tag should match `FASTVEP_REF_RELEASE` in `.env`.

Verify:

```bash
docker run --rm fastvep:grch38-r115 fastvep --version
docker run --rm fastvep:grch38-r115 fastvep-annotate --help
```

---

## 3. Push to Docker Hub

```bash
docker login
export DOCKERHUB_USER=<your-dockerhub-user-or-org>
cd docker/databricks
./build-and-push.sh
```

Or manually:

```bash
docker tag fastvep:grch38-r115 ${DOCKERHUB_USER}/fastvep:grch38-r115
docker push ${DOCKERHUB_USER}/fastvep:grch38-r115
```

PowerShell:

```powershell
$env:DOCKERHUB_USER = "<org>"
cd C:\Users\DangKim\Workspace\fastVEP\docker\databricks
.\build-and-push.ps1
```

**Databricks:** Compute → cluster → Docker → Image URL  
`docker.io/<DOCKERHUB_USER>/fastvep:grch38-r115`

---

## 4. Runtime (Glow Pipe / shell)

```bash
fastvep-annotate \
  --input /path/to/input.vcf \
  --output /path/to/output.vcf \
  --output-format vcf
```

Output is written to the path you pass as `--output` (e.g. `dbfs:/...` on Databricks).

---

## 5. Local smoke test

Mount the **repo root** and use a VCF that exists (e.g. `validation/human/vep_example_GRCh38.vcf` — small).

Bash:

```bash
docker run --rm \
  -v "/path/to/fastVEP:/work" \
  fastvep:grch38-r115 \
  fastvep-annotate \
    --input /work/validation/human/vep_example_GRCh38.vcf \
    --output /work/annotated-smoke.vcf \
    --output-format vcf
```

PowerShell:

```powershell
docker run --rm -v "C:\Users\YourUsername\Workspace\fastVEP:/work" fastvep:your-real-tag fastvep-annotate --input /work/validation/human/vep_example_GRCh38.vcf --output /work/annotated-smoke.vcf --output-format vcf
```

Please replace your tag with true after building the image in the command above before running the image.

Result on host: `C:\Users\YourUsername\Workspace\fastVEP\annotated-smoke.vcf` (or your mount path).

---

## 6. New reference release

1. Edit **`.env`** (`FASTVEP_REF_RELEASE`, filenames under `${FASTVEP_REFERENCE_DIR}`).
2. Copy new files into `reference/`.
3. `./build-reference-cache.sh`
4. `docker build` + push with the new tag.

Rebuild the transcript cache for every new GFF3 + FASTA pair.

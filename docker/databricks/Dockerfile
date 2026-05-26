# fastVEP on Glow for Databricks. Reference paths: edit .env only.
FROM containerregistrypubliccb.azurecr.io/glow:latest

COPY fastvep /usr/local/bin/fastvep
COPY fastvep-annotate /usr/local/bin/fastvep-annotate
COPY .env /opt/fastvep/.env
COPY reference/ /opt/fastvep/reference/

RUN sed -i 's/\r$//' /usr/local/bin/fastvep-annotate /opt/fastvep/.env \
    && chmod +x /usr/local/bin/fastvep /usr/local/bin/fastvep-annotate

RUN set -eux; \
    set -a; . /opt/fastvep/.env; set +a; \
    test -s /usr/local/bin/fastvep; \
    test -s "$GFF3"; \
    test -s "$FASTA"; \
    test -s "${FASTA}.fai"; \
    test -s "$TRANSCRIPT_CACHE"; \
    /usr/local/bin/fastvep --version

ENV FASTVEP_ENV_FILE=/opt/fastvep/.env

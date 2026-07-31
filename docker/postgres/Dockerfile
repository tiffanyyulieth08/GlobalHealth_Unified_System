FROM postgres:16-bookworm

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        postgresql-plpython3-16 \
        python3-lxml \
    && rm -rf /var/lib/apt/lists/*

COPY docker/postgres/primary/init/ /docker-entrypoint-initdb.d/

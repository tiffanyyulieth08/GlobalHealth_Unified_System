FROM postgres:16-bookworm

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        postgresql-contrib-16 \
    && rm -rf /var/lib/apt/lists/*

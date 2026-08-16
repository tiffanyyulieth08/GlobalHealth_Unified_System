FROM postgres:16-bookworm

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
        postgresql-plpython3-16 \
        python3-lxml \
    && rm -rf /var/lib/apt/lists/*

COPY docker/postgres/primary/init/ /docker-entrypoint-initdb.d/
COPY database/postgres/mor/ /opt/globalhealth/postgres/mor/
COPY database/postgres/xml/ /opt/globalhealth/postgres/xml/
COPY docker/postgres/primary/postgresql.conf /etc/postgresql/primary-postgresql.conf
COPY docker/postgres/primary/pg_hba.conf /etc/postgresql/primary-pg_hba.conf
COPY docker/postgres/replica/entrypoint.sh /usr/local/bin/replica-entrypoint.sh

RUN chmod +x /docker-entrypoint-initdb.d/*.sh /usr/local/bin/replica-entrypoint.sh

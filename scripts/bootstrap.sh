#!/bin/sh
set -eu

if [ ! -f .env ]; then
    cp .env.example .env
fi

docker compose up -d --build
docker compose ps

#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

KEEP_TEST_ENV="${KEEP_TEST_ENV:-0}"
COMPOSE_PREFIX="${TEST_COMPOSE_PREFIX:-globalhealth-test}"

# Ejecuta una suite dentro de un proyecto Compose aislado. Detiene la puerta
# ante el primer error, indica que suite fallo y limpia los volumenes
# temporales del proyecto (salvo que KEEP_TEST_ENV=1).
run_suite() {
    suite="$1"
    envvar="$2"
    shift 2
    project="${COMPOSE_PREFIX}-${suite}"
    echo
    echo "==> [${suite}] proyecto aislado: ${project}"
    if ! env "$envvar=$project" "$@"; then
        echo "FAIL: suite '${suite}' fallo (proyecto ${project})" >&2
        exit 1
    fi
    if [ "$KEEP_TEST_ENV" != "1" ]; then
        docker compose -p "$project" down -v --remove-orphans >/dev/null 2>&1 || true
    fi
    echo "==> [${suite}] PASS"
}

echo "==> Puerta de calidad: validando compose config"
docker compose config --quiet
echo "OK: compose config valido"

run_suite replication REPLICATION_COMPOSE_PROJECT sh scripts/test-replication.sh
run_suite mor MOR_COMPOSE_PROJECT sh scripts/test-mor.sh
run_suite xml-xsd XML_XSD_COMPOSE_PROJECT sh scripts/test-xml-xsd.sh
run_suite mongodb MONGODB_COMPOSE_PROJECT sh scripts/test-mongodb.sh
run_suite fragmentation-horizontal FRAGMENTATION_COMPOSE_PROJECT sh scripts/test-fragmentation-horizontal.sh
run_suite fragmentation-vertical FRAGMENTATION_COMPOSE_PROJECT sh scripts/test-fragmentation-vertical.sh
run_suite integration INTEGRATION_COMPOSE_PROJECT sh tests/integration/run.sh

echo
echo "All test suites passed."

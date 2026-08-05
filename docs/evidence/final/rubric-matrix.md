# Matriz final de release

- timestamp: 2026-08-05T14:37:14-06:00
- commit: 36d75b21a2e63f32a53797bcee63d4c95fb84750
- branch: feature/atlas-security-final-release
- Alcance: commit base más los cambios no confirmados de esta revisión.
- result: **LISTO PARA PR HACIA develop**

## Evaluación final

| Rubro de la evaluación | Estado | Evidencia | Bloqueos |
| --- | --- | --- | --- |
| Arquitectura híbrida | PASS | `compose-config.txt`, `compose-ps.txt`, `health-databases.json` | Ninguno |
| Replicación Docker | PASS | `primary-status.txt`, `replica-status.txt`, `replication-test.log` | Ninguno |
| Fragmentación | PASS | `fragmentation-horizontal.log`, `fragmentation-vertical.log`, `integration-test.log` | Ninguno |
| MongoDB Atlas | PASS | `mongodb-atlas-test.log` | Ninguno |
| API segura | PASS | `backend-unit-test.log`, `integration-test.log`, `security-audit.txt` | Ninguno |
| Chaos Engineering | PASS | `chaos-test.log`, `dashboard-replica.json` | Ninguno; no existe promoción automática |
| Documentación | PASS | `README.md`, `AGENTS.md`, documentación final, arquitectura, Atlas y guía de defensa | Ninguno |

## Bloqueos y decisiones de release

- Atlas fue validado contra un clúster real con CRUD, índices, agregación, `$lookup` y salud sanitizada del backend.
- La eliminación global `docker compose down -v --remove-orphans` fue bloqueada por la protección de datos. Se verificó que `globalhealth-final-36d75b2` no tenía recursos previos y se construyó allí desde volúmenes nuevos, sin tocar proyectos existentes.
- No se creó `main`, no se hizo merge, commit, push ni tag. La rama de integración indicada sigue siendo `develop`.

## Auditoría de candidatos a eliminación

| Candidato | Decisión | Verificación |
| --- | --- | --- |
| `.gitkeep` en directorios con contenido | Eliminado | El directorio contiene archivos reales y no hay referencias al marcador |
| `backend/app/.gitkeep`, `backend/tests/.gitkeep`, `scripts/.gitkeep`, `database/postgres/mor/.gitkeep` | Eliminados | Código, pruebas y scripts ya mantienen los directorios |
| `.gitkeep` de fragmentación, Docker, arquitectura, cloud, defense y evidence | Eliminados | Cada ruta contiene o recibió archivos reales |
| `database/mongodb/seed`, `aggregations` y `tests` vacíos | Eliminados del árbol versionado al retirar sus únicos `.gitkeep` | Los scripts MongoDB vigentes están en `database/mongodb/*.js`; no existen referencias a esas carpetas |
| Evidencia histórica | Conservada | Es evidencia académica y puede apoyar la defensa; se identifica como histórica |
| Dependencias | Conservadas | `backend/requirements.txt` contiene cuatro dependencias distintas, sin duplicados |
| Variables de entorno | Dos entradas retiradas | `POSTGRES_WRITE_URL` y `POSTGRES_READ_URL` de `.env.example` no eran consumidas; Compose las construye con destinos separados |

## Inventario clasificado de archivos de entrega

Alcance: archivos versionados presentes y archivos nuevos de esta revisión. `.git/`, cachés ignoradas y datos de volúmenes Docker no forman parte del ZIP.

| Archivo | Clasificación |
| --- | --- |
| `.env.example` | configuración |
| `.gitattributes` | configuración |
| `.github/workflows/ci.yml` | configuración |
| `.gitignore` | configuración |
| `AGENTS.md` | documentación |
| `backend/app/__init__.py` | ejecución |
| `backend/app/config.py` | configuración |
| `backend/app/main.py` | ejecución |
| `backend/app/mongodb.py` | ejecución |
| `backend/app/routers/__init__.py` | ejecución |
| `backend/app/routers/telemetry.py` | ejecución |
| `backend/Dockerfile` | configuración |
| `backend/requirements.txt` | configuración |
| `backend/tests/test_config.py` | prueba |
| `backend/tests/test_mongodb.py` | prueba |
| `backend/tests/test_telemetry.py` | prueba |
| `compose.atlas.yaml` | configuración |
| `compose.yaml` | configuración |
| `database/mongodb/01_collections.js` | ejecución |
| `database/mongodb/02_seed.js` | ejecución |
| `database/mongodb/03_operations.js` | ejecución |
| `database/mongodb/04_aggregations.js` | ejecución |
| `database/mongodb/05_tests.js` | prueba |
| `database/mongodb/atlas_validation.js` | prueba |
| `database/postgres/fragmentation/horizontal/coordinator/01_setup.sh` | ejecución |
| `database/postgres/fragmentation/horizontal/north/01_schema.sql` | ejecución |
| `database/postgres/fragmentation/horizontal/north/02_roles.sh` | ejecución |
| `database/postgres/fragmentation/horizontal/north/03_seed.sql` | ejecución |
| `database/postgres/fragmentation/horizontal/south/01_schema.sql` | ejecución |
| `database/postgres/fragmentation/horizontal/south/02_roles.sh` | ejecución |
| `database/postgres/fragmentation/horizontal/south/03_seed.sql` | ejecución |
| `database/postgres/fragmentation/vertical/coordinator/01_setup.sh` | ejecución |
| `database/postgres/fragmentation/vertical/financial/01_schema.sql` | ejecución |
| `database/postgres/fragmentation/vertical/financial/02_roles.sh` | ejecución |
| `database/postgres/fragmentation/vertical/financial/03_seed.sql` | ejecución |
| `database/postgres/fragmentation/vertical/public/01_schema.sql` | ejecución |
| `database/postgres/fragmentation/vertical/public/02_roles.sh` | ejecución |
| `database/postgres/fragmentation/vertical/public/03_seed.sql` | ejecución |
| `database/postgres/mor/01_types.sql` | ejecución |
| `database/postgres/mor/02_tables.sql` | ejecución |
| `database/postgres/mor/03_functions.sql` | ejecución |
| `database/postgres/mor/04_seed.sql` | ejecución |
| `database/postgres/mor/05_crud.sql` | ejecución |
| `database/postgres/mor/06_tests.sql` | prueba |
| `database/postgres/xml/01_schema_registry.sql` | ejecución |
| `database/postgres/xml/02_clinical_records.sql` | ejecución |
| `database/postgres/xml/03_xml_operations.sql` | ejecución |
| `database/postgres/xml/04_tests.sql` | prueba |
| `database/postgres/xml/schemas/clinical-record-v1.xsd` | ejecución |
| `docker/postgres/Dockerfile` | configuración |
| `docker/postgres/fragmentation/coordinator/Dockerfile` | configuración |
| `docker/postgres/primary/init/001-enable-plpython.sql` | ejecución |
| `docker/postgres/primary/init/002-create-replication-user.sh` | ejecución |
| `docker/postgres/primary/pg_hba.conf` | configuración |
| `docker/postgres/primary/postgresql.conf` | configuración |
| `docker/postgres/replica/entrypoint.sh` | ejecución |
| `docs/architecture/postgresql-primary-replica.md` | documentación |
| `docs/cloud/mongodb-atlas.md` | documentación |
| `docs/defense/demo-guide.md` | documentación |
| `docs/evidence/final/backend-unit-test.log` | generado |
| `docs/evidence/final/chaos-test.log` | generado |
| `docs/evidence/final/compose-config.txt` | generado |
| `docs/evidence/final/compose-ps.txt` | generado |
| `docs/evidence/final/dashboard-replica.json` | generado |
| `docs/evidence/final/fragmentation-horizontal.log` | generado |
| `docs/evidence/final/fragmentation-vertical.log` | generado |
| `docs/evidence/final/health-databases.json` | generado |
| `docs/evidence/final/integration-test.log` | generado |
| `docs/evidence/final/mongodb-atlas-test.log` | generado |
| `docs/evidence/final/mongodb-local-test.log` | generado |
| `docs/evidence/final/mor-test.log` | generado |
| `docs/evidence/final/primary-status.txt` | generado |
| `docs/evidence/final/replica-status.txt` | generado |
| `docs/evidence/final/replication-test.log` | generado |
| `docs/evidence/final/rubric-matrix.md` | generado |
| `docs/evidence/final/security-audit.txt` | generado |
| `docs/evidence/final/xml-xsd-test.log` | generado |
| `docs/evidence/integration/backend.txt` | evidencia |
| `docs/evidence/integration/dashboard.json` | evidencia |
| `docs/evidence/integration/fragmentation-horizontal.txt` | evidencia |
| `docs/evidence/integration/fragmentation-vertical.txt` | evidencia |
| `docs/evidence/integration/lookup.json` | evidencia |
| `docs/evidence/integration/mongodb-setup.txt` | evidencia |
| `docs/evidence/integration/patient.json` | evidencia |
| `docs/evidence/integration/postgresql.txt` | evidencia |
| `docs/evidence/integration/README.md` | evidencia |
| `docs/evidence/integration/security.txt` | evidencia |
| `docs/evidence/integration/sensor-log-1.json` | evidencia |
| `docs/evidence/integration/sensor-log-2.json` | evidencia |
| `docs/evidence/integration/session.json` | evidencia |
| `docs/evidence/replication-chaos/01-initial-health-http.txt` | evidencia |
| `docs/evidence/replication-chaos/01-initial-health.json` | evidencia |
| `docs/evidence/replication-chaos/02-primary-insert.txt` | evidencia |
| `docs/evidence/replication-chaos/03-replica-observation.txt` | evidencia |
| `docs/evidence/replication-chaos/04-primary-stop.txt` | evidencia |
| `docs/evidence/replication-chaos/05-dashboard-http.txt` | evidencia |
| `docs/evidence/replication-chaos/05-dashboard-replica.json` | evidencia |
| `docs/evidence/replication-chaos/06-rejected-write-http.txt` | evidencia |
| `docs/evidence/replication-chaos/06-rejected-write.json` | evidencia |
| `docs/evidence/replication-chaos/07-primary-start.txt` | evidencia |
| `docs/evidence/replication-chaos/08-primary-recovery.txt` | evidencia |
| `docs/evidence/replication-chaos/09-streaming-restored.txt` | evidencia |
| `docs/evidence/replication-chaos/README.md` | evidencia |
| `docs/final-documentation.md` | documentación |
| `README.md` | documentación |
| `scripts/bootstrap.sh` | ejecución |
| `scripts/chaos-replication.sh` | prueba |
| `scripts/replication-status.sh` | ejecución |
| `scripts/test-all.sh` | prueba |
| `scripts/test-fragmentation-horizontal.sh` | prueba |
| `scripts/test-fragmentation-vertical.sh` | prueba |
| `scripts/test-fragmentation.sh` | prueba |
| `scripts/test-mongodb-atlas.sh` | prueba |
| `scripts/test-mongodb.sh` | prueba |
| `scripts/test-mor.sh` | prueba |
| `scripts/test-replication.sh` | prueba |
| `scripts/test-xml-xsd.sh` | prueba |
| `scripts/wait-for-service.sh` | ejecución |
| `tests/integration/postgres_flow.sql` | prueba |
| `tests/integration/run.sh` | prueba |

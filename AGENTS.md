# AGENTS.md

Guia para agentes de IA y desarrolladores que trabajan en GlobalHealth Unified System.

## Reglas generales

- No hacer `git commit` ni `git push` salvo que se indique explicitamente.
- Trabajar siempre en la rama propia de cada responsable (p. ej. `feature/tiffany-repository-structure`).
- Antes de cerrar una tarea: ejecutar `git status --short` y `git diff --check`.
- No agregar comentarios de codigo salvo que se pidan.
- No crear archivos o documentacion innecesaria; solo lo requerido por la tarea.

## Estado actual del proyecto

Fase de integración y release. Están implementados:

- MOR con tipos compuestos, tabla tipada, herencia, arreglos, funciones, CRUD y pruebas.
- XML/XSD con registro de esquemas, validación mediante `plpython3u`/`lxml`,
  XPath, `XMLTABLE`, operaciones y pruebas positivas y negativas.
- MongoDB local y Atlas con colecciones, validadores, índices, CRUD,
  agregaciones, API FastAPI y prueba Atlas aislada.
- PostgreSQL Primary/Replica con streaming asíncrono, separación de conexiones
  de lectura/escritura, estado operativo y prueba de caos sin promoción.
- Fragmentación horizontal y vertical con coordinadores `postgres_fdw`,
  reconstrucción y pruebas de duplicados y huérfanos.
- Pruebas unitarias, por subsistema e integración mediante Docker Compose.

La evidencia actual de una entrega debe generarse en `docs/evidence/final/`.
Los directorios `docs/evidence/integration/` y
`docs/evidence/replication-chaos/` contienen ejecuciones históricas y no
sustituyen la validación final.

## Estructura esperada

| Ruta                                  | Proposito                                   |
| ------------------------------------- | ------------------------------------------- |
| `backend/app/`                        | Codigo fuente del backend                   |
| `backend/tests/`                      | Pruebas del backend                         |
| `database/postgres/mor/`              | Scripts MOR                                 |
| `database/postgres/xml/schemas/`      | Esquemas XML/XSD                            |
| `database/postgres/fragmentation/`    | Scripts de fragmentacion (horizontal/vertical) |
| `database/mongodb/`                   | Seed, agregaciones y pruebas de MongoDB      |
| `docker/postgres/`                    | Configuracion de primario y replica          |
| `docs/`                               | Arquitectura, cloud, defensa y evidencia     |
| `scripts/`                            | Scripts de apoyo                             |
| `.github/workflows/`                  | CI/CD                                       |
| `compose.yaml`                        | Orquestacion con Docker Compose             |

## Verificacion

- `docker compose config --quiet` para validar la orquestación.
- `sh scripts/test-all.sh` para la puerta funcional local completa.
- `sh scripts/chaos-replication.sh` para la recuperación controlada.
- `sh scripts/test-mongodb-atlas.sh` solo con una URI Atlas real.
- `git status --short` para revisar cambios pendientes.
- `git diff --check` para detectar problemas de espacios/conflictos.

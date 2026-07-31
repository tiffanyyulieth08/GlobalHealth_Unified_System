# AGENTS.md

Guia para agentes de IA y desarrolladores que trabajan en GlobalHealth Unified System.

## Reglas generales

- No hacer `git commit` ni `git push` salvo que se indique explicitamente.
- Trabajar siempre en la rama propia de cada responsable (p. ej. `feature/tiffany-repository-structure`).
- Antes de cerrar una tarea: ejecutar `git status --short` y `git diff --check`.
- No agregar comentarios de codigo salvo que se pidan.
- No crear archivos o documentacion innecesaria; solo lo requerido por la tarea.

## Estado actual del proyecto

Fase inicial: solo estructura del repositorio y archivos base. No implementado todavia:

- MOR (Modelo Objeto Relacional).
- XML/XSD.
- MongoDB.
- Replicacion PostgreSQL.
- Fragmentacion (horizontal y vertical).

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

- `git status --short` para revisar cambios pendientes.
- `git diff --check` para detectar problemas de espacios/conflictos.

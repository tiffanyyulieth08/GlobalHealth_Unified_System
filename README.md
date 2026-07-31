# GlobalHealth Unified System

## Descripcion del proyecto

GlobalHealth Unified System es un sistema que unifica la gestion de datos de salud mediante
una arquitectura de base de datos avanzada. Combina un modelo objeto-relacional (MOR) en
PostgreSQL, esquemas XML/XSD, integracion con MongoDB, replicacion PostgreSQL y estrategias
de fragmentacion horizontal y vertical para garantizar escalabilidad, integridad y
disponibilidad de la informacion.

## Tecnologias

- PostgreSQL (MOR, XML/XSD, replicacion y fragmentacion).
- MongoDB (almacenamiento no relacional, agregaciones).
- Python (backend).
- Docker y Docker Compose (contenedores y orquestacion).
- GitHub Actions (CI/CD).

## Responsables

| Nombre   | Rol / Rama                                            |
| -------- | ----------------------------------------------------- |
| Seidy    | Responsable del proyecto                              |
| Tiffany  | Responsable del proyecto                              |

## Estructura del repositorio

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

## Estado actual

Fase inicial: solo estructura del repositorio y archivos base.

No implementado todavia:

- MOR (Modelo Objeto Relacional).
- XML/XSD.
- MongoDB.
- Replicacion PostgreSQL.
- Fragmentacion (horizontal y vertical).

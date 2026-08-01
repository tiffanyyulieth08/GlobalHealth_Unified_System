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
- Python y FastAPI (backend).
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

## Requisitos

- Docker Engine o Docker Desktop.
- Docker Compose v2.
- `curl` para comprobar el endpoint del backend.
- `mongosh` si se prueban scripts directamente contra MongoDB Atlas.
- Puerto local `8000` disponible.

## Configuracion

Crear el archivo de entorno local a partir del ejemplo:

```bash
cp .env.example .env
```

En PowerShell:

```powershell
Copy-Item .env.example .env
```

Antes de iniciar los servicios, actualiza en `.env` al menos
`POSTGRES_PASSWORD` y `POSTGRES_REPLICATION_PASSWORD`. Conserva
`POSTGRES_WRITE_URL` apuntando al primario y `POSTGRES_READ_URL` apuntando a la
replica. `MONGODB_URI` usa por defecto el servicio local sin credenciales; para
Atlas debe reemplazarse mediante una variable de entorno o un gestor de
secretos.

## Uso con Docker Compose

Construir las imagenes:

```bash
docker compose build
```

Iniciar los servicios:

```bash
docker compose up -d
```

Tambien se puede crear `.env`, construir e iniciar en un solo paso:

```bash
sh scripts/bootstrap.sh
```

Comprobar el estado de los servicios:

```bash
docker compose ps
curl http://localhost:8000/health
curl http://localhost:8000/health/databases
curl http://localhost:8000/api/mongodb/health
```

Detener los servicios:

```bash
docker compose down
```

Los volumenes `postgres-primary-data`, `postgres-replica-data` y
`mongodb-data` conservan los datos al detener los contenedores.

## Estado actual

La infraestructura Docker incluye PostgreSQL Primary/Replica con streaming
replication, MongoDB para telemetria medica y un backend FastAPI que separa
escrituras PostgreSQL, lecturas desde la replica y operaciones MongoDB.

### Fase 1: MOR y XML/XSD

- **MOR (Modelo Objeto-Relacional)** en `database/postgres/mor/`: tipos
  compuestos (`address_t`, `phone_t`, `equipment_t`, `clinic_t`), tabla tipada
  con `CREATE TABLE ... OF`, herencia (`employee` / `doctor`), composicion
  clinica-equipos, arreglos de especialidades y telefonos, funciones que reciben
  tipos compuestos, datos semilla, operaciones CRUD y pruebas positivas y
  negativas.
- **XML/XSD** en `database/postgres/xml/`: registro de esquemas XSD,
  validacion de registros clinicos contra el XSD (plpython3 + lxml),
  operaciones XML (XPath, `XMLTABLE`) y pruebas automatizadas.

#### Probar MOR

```bash
sh scripts/test-mor.sh
```

El script crea la base temporal `globalhealth_mor_test`, aplica en orden los
scripts de `database/postgres/mor/` (`01_types.sql`, `02_tables.sql`,
`03_functions.sql`, `04_seed.sql`, `05_crud.sql`) y ejecuta `06_tests.sql`, que
incluye aserciones positivas y negativas. Al finalizar elimina la base temporal.
Requiere Docker Compose con el servicio `postgres-primary`.

Opcionalmente, para usar un `psql` externo:

```bash
MOR_PSQL="psql -h localhost -U globalhealth" MOR_DB=globalhealth_mor_test \
  sh scripts/test-mor.sh
```

#### Probar XML/XSD

```bash
sh scripts/test-xml-xsd.sh
```

El script crea la base temporal `globalhealth_xml_xsd_test`, registra el esquema
`clinical-record-v1` desde `database/postgres/xml/schemas/` y ejecuta las
pruebas de `04_tests.sql`. Al finalizar elimina la base temporal.

Las pruebas verifican que:

- los documentos XML validos se insertan y se consultan por XPath y `XMLTABLE`;
- el XML malformado es rechazado;
- el XML bien formado pero invalido segun el XSD tambien es rechazado.

Opcionalmente, para usar un `psql` externo:

```bash
XML_XSD_PSQL="psql -h localhost -U globalhealth" XML_XSD_DB=globalhealth_xml_xsd_test \
  sh scripts/test-xml-xsd.sh
```

### Fase 2: PostgreSQL Primary/Replica y MongoDB

- **PostgreSQL Primary/Replica**: el primario genera WAL y la replica se
  inicializa con `pg_basebackup` en modo hot standby. El backend usa
  `POSTGRES_WRITE_URL` para escrituras y `POSTGRES_READ_URL` para lecturas. El
  endpoint `GET /dashboard` permanece conectado a la replica y
  `GET /health/databases` comprueba el rol de ambas instancias.
- **MongoDB**: las colecciones `patients`, `sessions` y `sensor_logs` incluyen
  validadores, relaciones logicas mediante `patientId` y `sessionId`, indices,
  semillas, CRUD, filtros, limites, ordenamiento y agregaciones. El pipeline
  paciente → sesiones → logs esta disponible en los scripts y mediante
  `GET /api/patients/{patientId}/telemetry`.
- **FastAPI**: integra el router de telemetria MongoDB junto con los pools de
  escritura y lectura PostgreSQL. La conexion MongoDB se configura con
  `MONGODB_URI` y `MONGODB_DB`.

#### Probar replicacion

```bash
sh scripts/test-replication.sh
```

La prueba verifica que el primario no esta en recovery, que la replica si lo
esta y que un registro escrito en el primario llega a la replica. El estado
operativo tambien puede consultarse con:

```bash
sh scripts/replication-status.sh
```

#### Probar MongoDB

```bash
sh scripts/test-mongodb.sh
```

La prueba crea una base temporal, ejecuta colecciones, indices, semillas,
operaciones y agregaciones, valida el `$lookup` anidado y elimina la base al
terminar.

Consulta [la arquitectura Primary/Replica](docs/architecture/postgresql-primary-replica.md)
y [la guia de MongoDB Atlas](docs/cloud/mongodb-atlas.md) para despliegue y
operacion.

### Fase 3: pendiente

- Fragmentacion horizontal y vertical.

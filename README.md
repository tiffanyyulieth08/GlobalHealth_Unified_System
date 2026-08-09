# GlobalHealth Unified System

La [documentación final](docs/final-documentation.md) reúne la arquitectura,
fundamentos, despliegue, pruebas, defensa oral y matriz de trazabilidad.

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
- React, TypeScript, Vite y Nginx (frontend SPA).
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
| `frontend/`                           | SPA React, build multi-stage y Nginx        |
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
- `curl` para comprobar el frontend y los endpoints del backend.
- `mongosh` si se prueban scripts directamente contra MongoDB Atlas.
- Puertos locales `3000` (frontend) y `8000` (FastAPI) disponibles.
- Para la prueba integral: shell POSIX, `sed`, `grep` y `curl`; por defecto se
  usa los puertos locales `13000` y `18080`.

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
`POSTGRES_PASSWORD` y `POSTGRES_REPLICATION_PASSWORD`. Compose construye
`POSTGRES_WRITE_URL` hacia Primary y `POSTGRES_READ_URL` hacia Replica; no
intercambies esos destinos. Para MongoDB local conserva
`MONGODB_PROVIDER=local`. Para Atlas usa
`MONGODB_PROVIDER=atlas` y proporciona `MONGODB_URI` mediante una variable de
entorno o un gestor de secretos. La URI nunca debe entrar en Git.

La imagen del frontend recibe únicamente `VITE_API_BASE_URL`, que es una URL
pública compilada en la SPA y por defecto vale `http://localhost:8000`.
`FRONTEND_ORIGINS` debe contener exactamente el origen desde el que se abre la
SPA, por defecto `http://localhost:3000`; no es una lista de bases de datos ni
de hosts internos.

## Uso con Docker Compose

Construir las imagenes:

```bash
docker compose build
```

Iniciar los servicios:

```bash
docker compose up -d
```

Para Atlas, el override no inicia MongoDB local cuando se solicita únicamente
el backend:

```bash
MONGODB_URI="$MONGODB_URI" \
  docker compose -f compose.yaml -f compose.atlas.yaml up -d --build --wait backend
```

Tambien se puede crear `.env`, construir e iniciar en un solo paso:

```bash
sh scripts/bootstrap.sh
```

Comprobar el estado de los servicios:

```bash
docker compose ps
curl http://localhost:3000/
curl http://localhost:3000/clinical-records
curl http://localhost:8000/health
curl http://localhost:8000/health/databases
curl http://localhost:8000/api/mongodb/health
```

Abrir `http://localhost:3000`. Nginx sirve los archivos estáticos y devuelve
`index.html` para rutas de React como `/staff`, `/clinical-records`,
`/telemetry` y `/distribution`, por lo que un refresh directo funciona. Solo
el frontend y FastAPI publican puertos; PostgreSQL, MongoDB, coordinadores y
nodos de fragmentación permanecen en la red interna sin acceso directo desde
el navegador.

Detener los servicios:

```bash
docker compose down
```

Los volumenes `postgres-primary-data`, `postgres-replica-data` y
`mongodb-data` conservan los datos al detener los contenedores.

## Estado actual

La infraestructura Docker incluye la SPA React servida por Nginx, PostgreSQL
Primary/Replica con streaming replication, MongoDB para telemetria medica y un
backend FastAPI que separa escrituras PostgreSQL, lecturas desde la replica y
operaciones MongoDB. El navegador solo consume FastAPI; no conoce ni recibe
URLs o credenciales de las bases de datos.

Las vistas de demostración son:

| Vista | Tema presentado | Evidencia técnica asociada |
| --- | --- | --- |
| `/staff` | MOR: personal, especialidades y datos compuestos | `/api/mor/*` y `scripts/test-mor.sh` |
| `/clinical-records` | XML, validación XSD y consulta clínica | `/api/xml/*` y `scripts/test-xml-xsd.sh` |
| `/telemetry` | Pacientes, sesiones y sensores en MongoDB | `/api/patients/*`, `/api/sessions`, `/api/sensor-logs` |
| `/` | Primary/Replica, salud y dashboard leído desde Replica | `/health/databases` y `/dashboard` |
| `/distribution` | Fragmentación horizontal/vertical y coordinadores | `/api/fragmentation/*` y scripts de fragmentación |

Las vistas de módulo identifican las capacidades que se defienden; los
endpoints y scripts citados son la verificación funcional reproducible.

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
  semillas, CRUD, filtros por fecha, limites, ordenamiento y agregaciones. El pipeline
  paciente → sesiones → logs esta disponible en los scripts y mediante
  `GET /api/patients/{patientId}/telemetry`. El resumen para la defensa está en
  `GET /api/telemetry/summary` y muestra agrupación por paciente/sensor junto
  con un `$lookup` del paciente.
- **FastAPI**: integra el router de telemetria MongoDB junto con los pools de
  escritura y lectura PostgreSQL. La conexion MongoDB se configura con
  `MONGODB_PROVIDER`, `MONGODB_URI` y `MONGODB_DB`. El arranque exige un `ping`
  exitoso y el endpoint de salud nunca devuelve la URI.

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

#### Demostracion de caos de replicacion

Con Primary, Replica y el backend configurados mediante `.env`, ejecutar:

```bash
sh scripts/chaos-replication.sh
```

La demostracion realiza estos pasos:

1. Comprueba que Primary y Replica estan saludables.
2. Inserta un dato en Primary y espera hasta observarlo en Replica.
3. Detiene `postgres-primary` sin eliminar volumenes.
4. Consulta `/dashboard` y exige HTTP 200 desde Replica.
5. Intenta una escritura PostgreSQL por HTTP y exige HTTP 503.
6. Reinicia Primary y espera hasta que vuelva a estar saludable.
7. Confirma estado `streaming` en `pg_stat_replication` y
   `pg_stat_wal_receiver`.
8. Guarda las evidencias en `docs/evidence/replication-chaos/`.

La Replica no se promueve en ningun momento. El script registra un `trap` de
salida que reinicia Primary incluso si la demostracion falla o es interrumpida.
No ejecuta `docker compose down` ni elimina volumenes.

Si se utiliza un proyecto Compose con nombre explicito:

```bash
CHAOS_COMPOSE_PROJECT=globalhealth sh scripts/chaos-replication.sh
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

### Fase 3: Fragmentacion de datos

La fragmentacion separa los datos de pacientes en nodos PostgreSQL dedicados. Cada
nodo es un contenedor independiente dentro de `globalhealth-network` y se accede
mediante `postgres_fdw` desde un nodo coordinador.

#### Nodos de fragmentacion

| Servicio                              | Base                       | Proposito                              |
| ------------------------------------- | -------------------------- | -------------------------------------- |
| `fragment-public`                     | `globalhealth_public`      | Fragmento vertical con datos publicos  |
| `fragment-financial`                  | `globalhealth_financial`   | Fragmento vertical confidencial        |
| `fragment-north`                      | `globalhealth_north`       | Fragmento horizontal region `NORTH`    |
| `fragment-south`                      | `globalhealth_south`       | Fragmento horizontal region `SOUTH`    |
| `fragmentation-coordinator`           | `globalhealth`             | Coordinador vertical (`postgres_fdw`)  |
| `fragmentation-coordinator-horizontal`| `globalhealth_horizontal`  | Coordinador horizontal (`postgres_fdw`)|

#### Fragmentacion vertical

`patients_public` (datos publicos) y `patients_financial` (datos financieros) usan
`patient_id` como llave primaria. Roles separados: `public_role` solo lee datos
publicos y `financial_role` solo lee datos financieros; el rol publico no accede a
informacion financiera.

#### Reconstruccion vertical mediante JOIN

El coordinador `fragmentation-coordinator` expone las foreign tables
`patients_public` y `patients_financial` y la vista `patients_full`, que reconstruye
el paciente completo con `JOIN ... USING (patient_id)`.

#### Fragmentacion horizontal

`patients` en `fragment-north` restringe `region = 'NORTH'` y en `fragment-south`
`region = 'SOUTH'` mediante restricciones CHECK. La columna `region` es obligatoria.
El coordinador enruta las inserciones con la funcion `insert_patient()` segun la
region y rechaza regiones no soportadas.

#### Reconstruccion horizontal mediante UNION ALL

El coordinador `fragmentation-coordinator-horizontal` expone las foreign tables
`patients_north` y `patients_south` y la vista `patients_all`, que reconstruye todos
los pacientes con `UNION ALL`.

#### Ejecutar las pruebas

```bash
sh scripts/test-fragmentation-vertical.sh
sh scripts/test-fragmentation-horizontal.sh
```

Para ejecutar ambas en secuencia:

```bash
sh scripts/test-fragmentation.sh
```

#### Resultados esperados

La prueba vertical confirma 6 registros en cada fragmento, la reconstrucción de 6
pacientes completos mediante JOIN, ausencia de huérfanos en el estado normal,
detección temporal de huérfanos con `ROLLBACK` y que el rol público no accede a
información financiera. La prueba horizontal confirma las
restricciones CHECK por region, el enrutamiento de inserciones segun la region, el
rechazo de inserciones en el nodo equivocado, la deteccion de `patient_id`
duplicado entre nodos y la reconstruccion global de 10 registros mediante
`UNION ALL`. Ambas terminan con `All fragmentation ... tests passed.` y salida 0.

## Prueba de integracion completa

Con Docker activo, ejecutar:

```bash
sh scripts/test-all.sh
```

La prueba crea un entorno Docker aislado y verifica en un solo flujo el frontend
y su fallback SPA, FastAPI y CORS, los roles Primary/Replica, la creación del
médico en PostgreSQL Primary, la aceptación y rechazo XML/XSD, la telemetría en
MongoDB con `$lookup`, la consulta del dashboard desde Replica, ambas
reconstrucciones de fragmentación y la ausencia de credenciales en respuestas,
logs y archivos estáticos de la imagen. Las evidencias sanitizadas quedan en
`docs/evidence/integration/`.

El entorno se elimina junto con sus volúmenes al terminar. Para conservarlo con
fines de diagnóstico:

```bash
KEEP_INTEGRATION_ENV=1 sh scripts/test-all.sh
```

## Validación final y entrega

La guía reproducible de la defensa está en
[`docs/defense/demo-guide.md`](docs/defense/demo-guide.md). Antes de preparar
una entrega:

```bash
git diff --check
docker compose config --quiet
docker compose down -v --remove-orphans
docker compose up -d --build --wait --wait-timeout 240
sh scripts/test-all.sh
sh scripts/chaos-replication.sh
sh scripts/test-mongodb-atlas.sh
```

El último comando requiere una URI Atlas real. Una salida `BLOCKED` o `FAIL` no
se puede presentar como evidencia exitosa. La evidencia de esta versión se
guarda en `docs/evidence/final/` con fecha, rama, commit probado y resultado.
Las carpetas de evidencia anteriores son históricas.

Para un reset controlado de Replica, sin eliminar Primary, seguir
[`docs/architecture/postgresql-primary-replica.md`](docs/architecture/postgresql-primary-replica.md).

### ZIP sin Git ni secretos

Desde el directorio padre, en una shell POSIX:

```bash
zip -r GlobalHealth_Unified_System.zip GlobalHealth_Unified_System \
  -x 'GlobalHealth_Unified_System/.git/*' \
     'GlobalHealth_Unified_System/.env' \
     'GlobalHealth_Unified_System/.env.*' \
     'GlobalHealth_Unified_System/**/__pycache__/*' \
     'GlobalHealth_Unified_System/**/*.pyc'
```

En PowerShell:

```powershell
$source = Resolve-Path .\GlobalHealth_Unified_System
$stage = Join-Path $env:TEMP 'GlobalHealth_Unified_System-release'
robocopy $source $stage /E /XD .git __pycache__ /XF .env .env.local *.pyc
Compress-Archive -Path $stage -DestinationPath .\GlobalHealth_Unified_System.zip -Force
```

Verificar el contenido antes de distribuirlo:

```bash
unzip -l GlobalHealth_Unified_System.zip | grep -E '(^|/)\.git/|(^|/)\.env($|\.)'
```

El resultado esperado es vacío. `.git` no se elimina del repositorio de
trabajo; solo se excluye del artefacto.

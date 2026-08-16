# Documentación final — GlobalHealth Unified System

## 1. Alcance y criterio de evidencia

Este documento describe únicamente lo implementado en el repositorio. Los
comandos indican cómo verificarlo, pero su presencia no equivale a una ejecución
exitosa. `docs/evidence/integration/` y
`docs/evidence/replication-chaos/` son evidencia histórica; no prueban la versión
actual. La entrega vigente se registra en `docs/evidence/final/` con fecha, rama,
commit probado y resultado. Un bloqueo queda documentado como bloqueo, nunca como
`PASS`.

## 2. Arquitectura completa

```text
Navegador
    |
    v
Frontend SPA / Nginx :3000 ----HTTP/CORS----> FastAPI :8000
                                                |-- escrituras SQL ------> PostgreSQL Primary --WAL asíncrono--> Replica
                                                |-- dashboard SQL ---------------------------------------------> Replica
                                                `-- telemetría ----------> MongoDB local o MongoDB Atlas

Coordinador vertical --postgres_fdw--> fragment-public
                     `---------------> fragment-financial

Coordinador horizontal --postgres_fdw--> fragment-north
                       `---------------> fragment-south
```

Todos los contenedores de datos se comunican por la red interna
`globalhealth-network`. El backend pertenece además a
`globalhealth-edge-network`, donde recibe al frontend. El host publica Nginx en
`${FRONTEND_PORT:-3000}` y FastAPI en `${APP_PORT:-8000}`; ningún PostgreSQL,
MongoDB, coordinador ni nodo de fragmentación publica un puerto. El navegador
solo conoce la URL pública de FastAPI y el backend es el único componente con
URLs y credenciales de bases de datos. Los datos persistentes usan volúmenes
Docker.

| Componente | Responsabilidad | Implementación |
| --- | --- | --- |
| Frontend | SPA React, navegación y presentación de los subsistemas | `frontend/src/`, `frontend/Dockerfile`, `frontend/nginx.conf` |
| FastAPI | Salud, dashboard, escritura de caos y API de telemetría | `backend/app/main.py`, `backend/app/routers/telemetry.py` |
| PostgreSQL Primary | Escrituras, MOR, XML y emisión WAL | `docker/postgres/primary/`, `database/postgres/` |
| PostgreSQL Replica | Hot standby y consultas del dashboard | `docker/postgres/replica/` |
| MongoDB | Pacientes, sesiones y mediciones de sensores | `database/mongodb/`, `backend/app/mongodb.py` |
| Fragmentación vertical | Separación de datos públicos y financieros | `database/postgres/fragmentation/vertical/` |
| Fragmentación horizontal | Separación de pacientes NORTH y SOUTH | `database/postgres/fragmentation/horizontal/` |
| Coordinadores | Reconstrucción mediante `postgres_fdw` | scripts `coordinator/01_setup.sh` |

### Servicios Docker

| Servicio | Rol | Persistencia/puerto |
| --- | --- | --- |
| `frontend` | Build Vite y servidor SPA Nginx | sin persistencia, puerto `${FRONTEND_PORT:-3000}` |
| `postgres-primary` | Escrituras y emisor WAL | volumen `postgres-primary-data`, sin puerto host |
| `postgres-replica` | Hot standby y lecturas | volumen `postgres-replica-data`, sin puerto host |
| `mongodb` | Telemetría local | volumen `mongodb-data`, sin puerto host |
| `backend` | API y separación de pools | puerto `${APP_PORT:-8000}` |
| `fragment-public` / `fragment-financial` | Fragmentos verticales | un volumen por nodo |
| `fragmentation-coordinator` | Reconstrucción vertical | volumen propio |
| `fragment-north` / `fragment-south` | Fragmentos horizontales | un volumen por nodo |
| `fragmentation-coordinator-horizontal` | Reconstrucción horizontal | volumen propio |

### Estructura relevante del repositorio

| Ruta | Contenido |
| --- | --- |
| `frontend/src/` | Componentes, navegación y vistas React |
| `frontend/Dockerfile` | Build multi-stage Node/Vite → Nginx |
| `frontend/nginx.conf` | Servidor estático, healthcheck y fallback SPA |
| `backend/app/` | FastAPI y acceso exclusivo a las bases de datos |
| `database/` | MOR, XML/XSD, MongoDB y fragmentación |
| `docker/postgres/` | Primary, Replica y coordinadores |
| `tests/integration/` | Flujo integral frontend/backend/datos/seguridad |
| `docs/` | Arquitectura, operación, defensa y evidencia |

### Flujo de una operación

Las escrituras SQL usan el pool creado desde `POSTGRES_WRITE_URL`, que apunta a
`postgres-primary`. El endpoint `/dashboard` usa exclusivamente el pool creado
desde `POSTGRES_READ_URL`, que apunta a `postgres-replica`. La API de telemetría
usa `MONGODB_PROVIDER`, `MONGODB_URI` y `MONGODB_DB`, y comprueba MongoDB con
un `ping` al iniciar. No existe conmutación automática ni promoción de la
réplica.

La URL compilada de FastAPI se define con `VITE_API_BASE_URL` y vale
`http://localhost:8000` por defecto. Como es una URL que el navegador necesita,
no es secreta. `FRONTEND_ORIGINS` vale por defecto
`http://localhost:3000`; CORS no admite otros orígenes a menos que el operador
reemplace explícitamente ese valor. Nginx resuelve rutas desconocidas de la SPA
con `index.html`, de modo que un refresh de `/clinical-records` o
`/distribution` no produce 404.

### Vistas para la demostración

| Vista | Subsistema visible | Comprobación funcional |
| --- | --- | --- |
| `/staff` | MOR: personal, especialidades, contacto y composición | API `/api/mor/*` y `scripts/test-mor.sh` |
| `/clinical-records` | Documentos XML, validación XSD y consulta clínica | API `/api/xml/*` y `scripts/test-xml-xsd.sh` |
| `/telemetry` | Pacientes, sesiones y señales almacenadas en MongoDB | APIs de telemetría y `scripts/test-mongodb.sh` |
| `/` | Salud Primary/Replica, flujo WAL y métricas leídas desde Replica | `/health/databases`, `/dashboard` y prueba de replicación |
| `/distribution` | Fragmentación horizontal, vertical y coordinadores | `/api/fragmentation/*` y ambas pruebas de fragmentación |

Las pantallas de módulo presentan el mapa funcional para la defensa. La
evidencia de persistencia, reconstrucción y roles proviene de los endpoints y
scripts reproducibles de la última columna, no de texto estático de la SPA.

## 3. Modelo objeto-relacional (MOR)

El MOR conserva transacciones, restricciones y SQL de PostgreSQL, pero modela
objetos del dominio con capacidades objeto-relacionales:

- `address_t`, `phone_t`, `equipment_t` y `clinic_t` son tipos compuestos;
- `clinic` es una tabla tipada, creada con `CREATE TABLE ... OF clinic_t`;
- `doctor` hereda columnas de `employee` mediante `INHERITS`;
- una clínica compone un arreglo de `equipment_t`;
- los doctores tienen arreglos de especialidades y teléfonos;
- funciones como `format_address`, `register_equipment`,
  `clinic_equipment_count` y `yearly_salary` reciben tipos compuestos o filas.

Los scripts se aplican en orden: tipos, tablas, funciones, semilla, CRUD y
pruebas. `06_tests.sql` implementa aserciones y también verifica errores
esperados. PostgreSQL no propaga automáticamente todas las restricciones del
padre a una tabla heredada; por eso `doctor` declara de nuevo clave primaria,
unicidad de correo y validación de salario.

## 4. XML y XSD

`clinical-record-v1.xsd` define la estructura del expediente clínico. PostgreSQL
almacena el XSD en `xml_schema_registry` y el documento en
`clinical_records_xml`. Antes de insertar o actualizar, un trigger ejecuta
`validate_xml_against_schema`; la función usa `plpython3u` y `lxml` para validar
el documento contra el esquema registrado.

Hay dos niveles distintos de validez:

1. XML bien formado: etiquetas, atributos y anidamiento son sintácticamente
   correctos.
2. XML válido según XSD: además cumple elementos obligatorios, tipos, orden,
   namespace y restricciones del contrato.

Las vistas demuestran consulta nativa con `xpath`, filtrado con
`xpath_exists` y transformación relacional con `XMLTABLE`. Las funciones
`xml_replace_node_text` y `xml_remove_nodes` realizan cambios controlados; el
trigger vuelve a validar el resultado.

## 5. MongoDB

MongoDB almacena telemetría, cuyo volumen y forma de consulta encajan con
documentos y series de eventos:

- `patients`: identidad y estado del paciente;
- `sessions`: sesión y dispositivo, relacionada lógicamente por `patientId`;
- `sensor_logs`: mediciones, relacionadas por `sessionId` y `patientId`.

`01_collections.js` crea validadores JSON Schema e índices únicos y de consulta.
`02_seed.js` agrega datos repetibles con prefijo `SEED-`.
`03_operations.js` demuestra inserción, actualización, filtros, proyección,
orden y límite. `04_aggregations.js` implementa el pipeline paciente → sesiones
→ logs con `$lookup` anidado. `05_tests.js` comprueba validadores, índices,
relaciones esperadas y agregaciones.

MongoDB no aplica claves foráneas entre colecciones. La API compensa esa
decisión comprobando que el paciente exista antes de crear una sesión y que la
pareja sesión/paciente exista antes de insertar un log. Estas comprobaciones no
son equivalentes a una FK transaccional frente a escritores externos.

## 6. PostgreSQL Primary/Replica

El Primary usa `wal_level=replica`, procesos `wal_sender`, retención WAL y
autenticación SCRAM. En el primer arranque, la Replica ejecuta
`pg_basebackup`, crea `standby.signal` y entra en hot standby. El usuario de
replicación tiene `REPLICATION LOGIN`.

La réplica es asíncrona (`sync_state=async` en la evidencia disponible):
favorece disponibilidad y latencia de escritura, pero permite retraso y, ante
una pérdida irreversible del Primary, pérdida de transacciones aún no
reproducidas. La réplica no sustituye una copia de seguridad.

La prueba consulta `pg_is_in_recovery()` en ambos nodos, escribe una fila
temporal en Primary y espera hasta verla en Replica. El estado operativo se
consulta en `pg_stat_replication` y `pg_stat_wal_receiver`.

## 7. Fragmentación horizontal

Cada fila completa vive en un nodo determinado por `region`:

- `fragment-north`: `CHECK (region = 'NORTH')`;
- `fragment-south`: `CHECK (region = 'SOUTH')`.

El coordinador expone ambas tablas mediante `postgres_fdw`. La función
`insert_patient()` enruta cada inserción y rechaza regiones no soportadas; la
vista `patients_all` reconstruye el conjunto con `UNION ALL`.

```mermaid
flowchart LR
    API[FastAPI] -->|lectura| HC[Coordinador horizontal]
    HC -->|insert_patient: region = NORTH| N[(fragment-north<br/>patients<br/>CHECK NORTH)]
    HC -->|insert_patient: region = SOUTH| S[(fragment-south<br/>patients<br/>CHECK SOUTH)]
    N -->|postgres_fdw: patients_north| U[patients_all]
    S -->|postgres_fdw: patients_south| U
    U -->|UNION ALL| HC
```

El diagrama formal conserva la dirección del enrutamiento y de la
reconstrucción. Puede renderizarse directamente desde Mermaid al generar el PDF
final.

La implementación detecta un `patient_id` repetido entre nodos durante la
prueba, pero no ofrece una restricción global que impida todos los duplicados.
El enrutamiento centralizado es, por tanto, parte de la integridad del diseño.

## 8. Fragmentación vertical

Las columnas se separan por sensibilidad:

- `patients_public`: nombre, contacto, dirección y contacto de emergencia;
- `patients_financial`: aseguradora, póliza, facturación, saldo y forma de pago.

Ambos fragmentos usan `patient_id`. El coordinador crea foreign tables y la
vista `patients_full`, que reconstruye registros coincidentes con
`JOIN ... USING (patient_id)`. `public_role` solo puede leer el fragmento
público y `financial_role` el financiero. Un `INNER JOIN` excluye huérfanos;
las pruebas los cuentan explícitamente para hacer visible esa condición.

```mermaid
flowchart LR
    API[FastAPI] -->|lectura| VC[Coordinador vertical]
    P[(fragment-public<br/>patients_public<br/>identidad y contacto)] -->|postgres_fdw<br/>patient_id| J[patients_full]
    F[(fragment-financial<br/>patients_financial<br/>seguro y facturación)] -->|postgres_fdw<br/>patient_id| J
    J -->|INNER JOIN USING patient_id| VC
    PR[public_role] -->|SELECT permitido| P
    PR -.->|SELECT denegado| F
    FR[financial_role] -->|SELECT permitido| F
```

La llave de reconstrucción y la frontera de autorización quedan explícitas; el
diagrama puede incluirse sin cambios en una exportación Mermaid a SVG o PDF.

## 9. Teorema CAP aplicado

CAP indica que, cuando existe una partición de red, un sistema distribuido no
puede garantizar simultáneamente consistencia linealizable y disponibilidad
para todas las operaciones.

| Subsistema | Decisión observable ante una falla |
| --- | --- |
| Primary/Replica | Las lecturas del dashboard siguen disponibles desde una réplica potencialmente atrasada; las escrituras fallan con 503. Se prioriza disponibilidad de lectura, sin afirmar consistencia fuerte. |
| Fragmentación | El coordinador depende de los nodos remotos; una partición puede impedir reconstrucción o escritura. No hay tolerancia automática documentada. |
| MongoDB local | Es una sola instancia en Compose, por lo que no constituye un despliegue distribuido tolerante a particiones. |
| Atlas | La clasificación depende de topología, read concern y write concern seleccionados; no debe declararse AP o CP sin esa configuración. |

CAP solo obliga a elegir durante una partición. En operación normal sí pueden
coexistir consistencia y disponibilidad.

## 10. Modelo BASE aplicado

BASE significa disponibilidad básica, estado flexible y consistencia eventual.
Describe bien las lecturas desde la réplica asíncrona:

- disponibilidad básica: `/dashboard` puede responder aunque Primary esté
  detenido;
- estado flexible: Replica puede estar temporalmente atrasada;
- consistencia eventual: si la replicación se restablece y no aparecen nuevas
  fallas, los WAL pendientes se reproducen.

BASE no reemplaza ACID. Las escrituras clínicas del Primary siguen usando
transacciones y restricciones PostgreSQL; BASE caracteriza la convergencia
entre nodos.

## 11. Evaluación costo/beneficio de MongoDB Atlas

### Beneficios

- servicio administrado: aprovisionamiento, parches, monitoreo, alertas,
  respaldo y escalado reducen trabajo operativo;
- TLS, controles de red y usuarios por base facilitan una postura segura;
- alta disponibilidad y opciones multirregión evitan construir esa plataforma
  manualmente;
- métricas y Performance Advisor ayudan a ajustar índices con carga real.

### Costos y riesgos

- Atlas factura clústeres por hora y Flex por uso; región, proveedor, nivel,
  número de nodos, almacenamiento, respaldos y transferencia modifican el
  total;
- réplicas, multirregión, capacidad personalizada y transferencia saliente
  elevan el costo;
- existe dependencia del proveedor y costo de migración;
- Atlas no elimina obligaciones de gobierno de datos clínicos, clasificación,
  retención, auditoría y residencia.

### Cotización cuantitativa

Precios públicos verificados el **15 de agosto de 2026**, en **USD antes de
impuestos**. Es una comparación para desarrollo/prueba de bajo tráfico, no un
dimensionado clínico productivo. La alternativa autoadministrada es MongoDB
Community en un Droplet Basic de DigitalOcean; no representa el costo real del
MongoDB local de Compose, que depende del equipo, electricidad y tiempo de la
persona que lo opera. La alternativa administrada es un escenario cotizado con
Atlas Flex sobre AWS en una región admitida de Estados Unidos. El repositorio y
la evidencia sanitizada de conexión no permiten confirmar que el clúster Atlas
realmente desplegado sea Flex, ni revelan su proveedor o región.

Supuestos de la cotización: 30 días, hasta 5 GB de datos, hasta 100
operaciones/s, sin transferencia excedente y cuatro horas de administración de
la alternativa autoadministrada o una hora de administración Atlas al mes,
valoradas en USD 25/h. Las horas y la tarifa administrativa son supuestos
explícitos para hacer visible el trabajo, no mediciones del proyecto ni una
cotización de los proveedores.

| Alternativa | Cómputo mensual | Almacenamiento | Backups | Transferencia | Administración estimada | Total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| MongoDB Community autoadministrado — DigitalOcean Basic, 1 vCPU/2 GiB, región NYC | USD 12.00 | 50 GiB SSD incluidos: USD 0.00 | imagen diaria del Droplet, 30%: USD 3.60 | 2,000 GiB incluidos: USD 0.00 | 4 h × USD 25: USD 100.00 | **USD 115.60** |
| Atlas Flex cotizado — AWS, región admitida de EE. UU., carga base | USD 8.00 | 5 GB incluidos: USD 0.00 | 8 snapshots diarios retenidos: USD 0.00 | ilimitada incluida: USD 0.00 | 1 h × USD 25: USD 25.00 | **USD 33.00** |

Precios verificados: DigitalOcean publica USD 12/mes para 1 vCPU, 2 GiB RAM,
50 GiB SSD y 2,000 GiB de transferencia; la imagen diaria del Droplet cuesta
30% adicional. Esa imagen del servidor no equivale por sí sola a backup lógico,
backup continuo o recuperación a un punto en el tiempo de MongoDB. Atlas Flex
publica USD 8 por 30 días en la carga base, incluye 5 GB, 100 ops/s y
transferencia ilimitada, con tope de USD 30; Atlas conserva los últimos ocho
snapshots diarios. Atlas Flex solo admite un subconjunto de regiones.

| Banda de uso de Atlas Flex | Costo mensual publicado | Costo horario publicado |
| --- | ---: | ---: |
| 0–100 ops/s | USD 8.00 | USD 0.0110 |
| 100–200 ops/s | USD 15.00 | USD 0.0205 |
| 200–300 ops/s | USD 21.00 | USD 0.0288 |
| 300–400 ops/s | USD 26.00 | USD 0.0356 |
| 400–500 ops/s | USD 30.00 | USD 0.0411 |

Bajo los supuestos anteriores, Atlas Flex base reduce el costo directo de
infraestructura de USD 15.60 a USD 8.00 al mes: USD 7.60, o 48.7%. Al incluir
el tiempo administrativo supuesto, reduce el total de USD 115.60 a USD 33.00:
USD 82.60, o 71.5%. En la banda máxima de Flex, el total estimado sería USD
55.00 y la reducción frente al escenario autoadministrado sería USD 60.60, o
52.4%. Estos porcentajes son resultados del escenario, no ahorros observados en
la cuenta real.

### Medición local frente a Atlas

Medición ejecutada el **15 de agosto de 2026 a las 20:37 CST** desde el mismo
proceso PyMongo 4.13.0 dentro del contenedor del backend. Ambas alternativas
recibieron 500 documentos sintéticos iniciales con una carga útil de 512 bytes,
los mismos índices y las mismas operaciones. Para latencia se tomaron 100
muestras por operación. Para throughput se hicieron 200 intentos por operación
con concurrencia 8. Las bases temporales local y Atlas se eliminaron al
terminar. El resultado sanitizado completo está en
`docs/evidence/final/mongodb-cost-benefit-measurement.json`.

| Operación | Local p50 | Local p95 | Local p99 | Atlas p50 | Atlas p95 | Atlas p99 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Escritura | 0.179 ms | 0.328 ms | 0.361 ms | 88.938 ms | 91.504 ms | 105.972 ms |
| Lectura indexada | 0.225 ms | 0.493 ms | 0.558 ms | 88.098 ms | 99.401 ms | 122.127 ms |
| Agregación | 0.556 ms | 0.714 ms | 0.927 ms | 88.429 ms | 93.340 ms | 101.905 ms |

| Operación | Local ops/s | Atlas ops/s | Errores local | Errores Atlas |
| --- | ---: | ---: | ---: | ---: |
| Escritura | 2,727.909 | 27.025 | 0/200 | 0/200 |
| Lectura indexada | 2,945.543 | 86.108 | 0/200 | 0/200 |
| Agregación | 2,421.893 | 94.239 | 0/200 | 0/200 |

El resultado incluye la latencia de red entre el equipo de prueba y la región
Atlas, mientras que MongoDB local se encuentra en la misma red Docker. Por eso
cuantifica la experiencia de esta aplicación desde este equipo, no el límite de
capacidad universal de MongoDB ni de Atlas. Es una ejecución corta y no mide
disponibilidad mensual, comportamiento con datos clínicos ni rendimiento desde
clientes ubicados cerca de la región cloud.

La base Atlas configurada tenía, al momento de la consulta, 3 colecciones y 8
documentos: 2 pacientes, 2 sesiones y 4 logs. `dbStats` reportó 1,326 bytes de
datos lógicos, 110,592 bytes de almacenamiento y 253,952 bytes de índices. Estas
cifras describen únicamente la base lógica visible para el usuario de la
aplicación; no sustituyen el almacenamiento facturado del clúster que muestra
Atlas Billing.

### Evidencia cuantitativa pendiente y límites

La prueba Atlas conservada demuestra conexión, CRUD, índices, agregación,
`$lookup` y salud del backend. El benchmark posterior ya aporta latencia,
throughput y tasa de errores para una carga reproducible, pero la información
comercial de la cuenta no es accesible mediante la cadena de conexión de la
base. Se deben completar los siguientes campos sin usar la URI ni credenciales
como evidencia pública:

| Dato | Estado y evidencia necesaria |
| --- | --- |
| Tier, proveedor y región del clúster desplegado | **PENDIENTE:** captura o exportación sanitizada de la configuración de Atlas. |
| Uso y costo real | **PARCIAL:** `dbStats` documenta el tamaño lógico actual. **PENDIENTE:** almacenamiento facturado, ops/s promedio y pico del periodo, transferencia, fechas del periodo y total acumulado o facturado en Atlas Billing. |
| Latencia local frente a Atlas | **MEDIDO:** 100 muestras de escritura, lectura indexada y agregación por alternativa; conservar fecha, ubicación del cliente y método junto con los resultados. |
| Throughput local frente a Atlas | **MEDIDO:** 200 intentos por operación, concurrencia 8 y 0% de errores en ambas alternativas. Esta prueba corta no determina el máximo sostenible. |
| Disponibilidad y recuperación | **PARCIAL:** MongoDB publica un SLA de 99.995% para clústeres M10 o superiores. Su aplicación depende de confirmar el tier real. No se observó un periodo mensual ni se ejecutó failover o restauración Atlas; RPO, RTO y tiempo real de restauración siguen pendientes. |
| Esfuerzo operativo | **PENDIENTE:** horas reales dedicadas a instalación, parches, monitoreo, backup y recuperación en cada alternativa, si se quiere conservar este componente del cálculo. |

Fuentes consultadas el mismo día:

- https://www.digitalocean.com/pricing/droplets
- https://www.digitalocean.com/pricing/backups
- https://www.mongodb.com/docs/atlas/billing/atlas-flex-costs/
- https://www.mongodb.com/docs/atlas/backup/cloud-backup/flex-cluster-backup/
- https://www.mongodb.com/docs/atlas/production-notes/
- https://www.mongodb.com/docs/atlas/architecture/current/high-availability/

### Decisión recomendada

Para trabajo académico sin Internet, Compose local conserva reproducibilidad.
Para desarrollo conectado de baja carga, el escenario Atlas Flex reduce el
costo total estimado y delega tareas operativas, pero sus límites —5 GB, 500
ops/s máximas, sin backup continuo ni PITR— impiden extrapolar la tabla a
producción clínica. La recomendación es condicional: usar Flex para
desarrollo/prueba solo si la configuración y el consumo reales caben en esos
límites; mantener Compose para trabajo desconectado; y no recomendar todavía
la migración clínica productiva. Esa decisión requiere métricas comparables,
facturación real, una cotización dedicada y requisitos definidos de RPO/RTO,
residencia, auditoría y disponibilidad.

## 12. Despliegue completo

### Requisitos

Docker Engine/Desktop activo, Docker Compose v2, shell POSIX, `curl`, `sed` y
`grep`. `mongosh` solo es obligatorio al ejecutar directamente contra Atlas.

### Desarrollo local

```bash
git clone <URL_DEL_REPOSITORIO>
cd GlobalHealth_Unified_System
cp .env.example .env
```

En PowerShell, sustituir la copia por:

```powershell
Copy-Item .env.example .env
```

Editar `.env` y reemplazar al menos `POSTGRES_PASSWORD`,
`POSTGRES_REPLICATION_PASSWORD`, `FRAGMENT_FDW_PASSWORD` y
`FRAGMENT_HORIZONTAL_FDW_PASSWORD`. Mantener
`VITE_API_BASE_URL=http://localhost:8000` y
`FRONTEND_ORIGINS=http://localhost:3000` cuando se usan los puertos por defecto.
La imagen frontend no recibe ninguna URL interna ni credencial de base de datos.

```bash
docker compose config
docker compose build
docker compose up -d --wait
docker compose ps
curl --fail http://localhost:3000/
curl --fail http://localhost:3000/clinical-records
curl --fail http://localhost:8000/health
curl --fail http://localhost:8000/health/databases
curl --fail http://localhost:8000/api/mongodb/health
curl --fail http://localhost:8000/dashboard
```

La aplicación se abre en `http://localhost:3000`. La segunda comprobación
confirma el fallback de Nginx para refresh de rutas SPA. FastAPI permanece en
`http://localhost:8000`; los nodos de datos no tienen URL pública.

Alternativa de arranque:

```bash
sh scripts/bootstrap.sh
```

Detener conservando datos:

```bash
docker compose down
```

Eliminar volúmenes no forma parte del despliegue normal. Solo debe hacerse de
manera deliberada porque destruye los datos locales.

### MongoDB Atlas

Crear clúster, usuario `readWrite` limitado a `globalhealth` y lista de IP
restrictiva. Definir la URI sin imprimirla:

```bash
export MONGODB_URI='mongodb+srv://USUARIO:CONTRASENA@CLUSTER/globalhealth?retryWrites=true&w=majority'
export MONGODB_DB='globalhealth'
export MONGODB_PROVIDER='atlas'
sh scripts/test-mongodb-atlas.sh
```

En producción, la URI debe provenir de un gestor de secretos, no de Git ni de
la línea de comandos persistida por el shell. `compose.atlas.yaml` cambia el
backend a Atlas; al ejecutar `up ... backend`, el contenedor MongoDB local no es
una dependencia.

## 13. Comandos de pruebas

Cada script devuelve un código distinto de cero cuando una aserción falla.

```bash
sh scripts/test-mor.sh
sh scripts/test-xml-xsd.sh
sh scripts/test-mongodb.sh
sh scripts/test-mongodb-atlas.sh
sh scripts/test-replication.sh
sh scripts/replication-status.sh
sh scripts/test-fragmentation-vertical.sh
sh scripts/test-fragmentation-horizontal.sh
sh scripts/test-fragmentation.sh
sh scripts/test-all.sh
```

La prueba integral usa por defecto los puertos `13000` para la SPA y `18080`
para FastAPI. Comprueba frontend, refresh de ruta, CORS, backend, roles de
Primary/Replica, dashboard, MongoDB, fragmentación y ausencia de secretos en
respuestas, logs y archivos estáticos. Crea credenciales y un proyecto Compose
efímeros, guarda evidencia sanitizada y ejecuta `docker compose down -v` al
terminar. Para conservar el entorno:

```bash
KEEP_INTEGRATION_ENV=1 sh scripts/test-all.sh
```

Pruebas con clientes externos:

```bash
MOR_PSQL="psql -h localhost -U globalhealth" MOR_DB=globalhealth_mor_test sh scripts/test-mor.sh
XML_XSD_PSQL="psql -h localhost -U globalhealth" XML_XSD_DB=globalhealth_xml_xsd_test sh scripts/test-xml-xsd.sh
MONGODB_URI="$MONGODB_URI" sh scripts/test-mongodb-atlas.sh
```

No se debe dirigir una prueba destructiva a una base con datos que deban
conservarse.

## 14. Demostración de Chaos Engineering

Ejecutar con el entorno local saludable:

```bash
sh scripts/chaos-replication.sh
```

Con un nombre de proyecto Compose explícito:

```bash
CHAOS_COMPOSE_PROJECT=globalhealth sh scripts/chaos-replication.sh
```

El experimento define una hipótesis verificable: al detener Primary, el
dashboard seguirá disponible desde Replica y las escrituras fallarán de forma
controlada; al reiniciar Primary, el streaming se restaurará.

El script:

1. valida roles y salud;
2. escribe una sonda en Primary y la observa en Replica;
3. detiene Primary sin borrar volúmenes;
4. exige HTTP 200 y `source=replica` en `/dashboard`;
5. exige HTTP 503 al intentar una escritura;
6. reinicia Primary;
7. exige streaming en emisor y receptor;
8. realiza una escritura nueva y la confirma en Replica;
9. guarda artefactos y usa un `trap` para restaurar Primary ante error.

La evidencia versionada registra una ejecución previa con salud HTTP 200,
réplica `in_recovery=true`, dato replicado, dashboard HTTP 200 durante la caída,
escritura HTTP 503 y streaming asíncrono restaurado. Estos archivos no prueban
una ejecución en el equipo actual; para ello se debe volver a ejecutar el
comando y conservar su salida.

## 15. Preguntas y respuestas para defensa oral

**¿Por qué usar PostgreSQL y MongoDB?**

PostgreSQL protege datos estructurados y transaccionales; MongoDB permite
ingestar y consultar telemetría como documentos. La elección es por patrón de
datos, no porque una tecnología sustituya universalmente a la otra.

**¿Qué hace objeto-relacional al MOR?**

Tipos compuestos, tabla tipada, herencia, arreglos y funciones que operan sobre
tipos del dominio, manteniendo SQL y restricciones.

**¿Qué diferencia hay entre XML bien formado y válido?**

Bien formado cumple sintaxis XML; válido también cumple el contrato XSD.

**¿Por qué se usa `plpython3u` con `lxml`?**

PostgreSQL ofrece el tipo XML y XPath, pero el proyecto necesita validación XSD;
la función integra `lxml` y el trigger la hace obligatoria.

**¿Cómo se evita escribir en la réplica?**

La réplica está en recovery/hot standby y el backend separa pools: escritura al
Primary y dashboard a Replica.

**¿La réplica garantiza cero pérdida?**

No. Es asíncrona y puede existir WAL aún no reproducido.

**¿La réplica es un backup?**

No. Replica cambios y también puede propagar errores lógicos; se necesitan
backups y pruebas de restauración independientes.

**¿Qué ocurre si cae Primary?**

Las lecturas del dashboard continúan desde Replica, pero las escrituras
responden 503. No hay promoción automática.

**¿Cómo se reconstruye la fragmentación horizontal?**

Con una vista `UNION ALL` sobre foreign tables NORTH y SOUTH.

**¿Cómo se reconstruye la vertical?**

Con un `JOIN` por `patient_id` entre columnas públicas y financieras.

**¿Qué riesgo tienen los huérfanos verticales?**

Un `INNER JOIN` no los muestra. Las pruebas los detectan, pero una operación
distribuida requeriría controles adicionales.

**¿Qué riesgo tienen IDs repetidos horizontalmente?**

Las PK son locales a cada nodo. El coordinador debe enrutar y comprobar
unicidad global; la implementación actual demuestra la detección, no una
restricción distribuida absoluta.

**¿Dónde se ve CAP?**

Durante la caída del Primary se mantienen lecturas disponibles desde una copia
eventualmente consistente y se rechazan escrituras.

**¿BASE significa ausencia de ACID?**

No. BASE describe convergencia distribuida; las transacciones locales de
PostgreSQL siguen siendo ACID.

**¿Cuándo conviene Atlas?**

Cuando el valor de operación administrada, respaldo, monitoreo y alta
disponibilidad supera su costo total y se satisfacen requisitos clínicos y de
residencia.

**¿Cómo se evita inventar evidencia?**

Cada afirmación se vincula a una implementación y a un script reproducible; los
resultados solo se declaran cuando existe el artefacto generado.

## 16. Matriz de trazabilidad

| Requerimiento | Implementación | Prueba | Evidencia |
| --- | --- | --- | --- |
| Arquitectura desplegable | `compose.yaml`, Dockerfiles de frontend/backend, `docker/postgres/` | `docker compose config`, `docker compose ps` | Estado observado por el operador |
| Frontend SPA | `frontend/Dockerfile`, `frontend/nginx.conf`, `frontend/src/` | build Vite, `/`, refresh de `/clinical-records`, healthcheck | `frontend-index.html`, `frontend-spa-refresh.html` al ejecutar integración |
| URL API y CORS | `VITE_API_BASE_URL`, `FRONTEND_ORIGINS`, `backend/app/config.py` | orígenes permitido y rechazado en integración; pruebas unitarias | `cors-allowed.txt`, `cors-rejected.txt` al ejecutar integración |
| MOR | `database/postgres/mor/01_types.sql` a `05_crud.sql` | `scripts/test-mor.sh`, `06_tests.sql` | `docs/evidence/final/mor-test.log` |
| XML/XSD | `database/postgres/xml/`, `clinical-record-v1.xsd` | `scripts/test-xml-xsd.sh`, `04_tests.sql` | `docs/evidence/final/xml-xsd-test.log` |
| MongoDB | `database/mongodb/01_collections.js` a `04_aggregations.js` | `scripts/test-mongodb.sh`, `05_tests.js` | Salida de consola; integración puede generar JSON |
| API MongoDB | `backend/app/routers/telemetry.py` | `tests/integration/run.sh` | `docs/evidence/integration/*.json` después de ejecutar |
| Primary/Replica | `compose.yaml`, `docker/postgres/primary/`, `docker/postgres/replica/` | `scripts/test-replication.sh` | Salida de consola |
| Lecturas desde Replica | endpoint `/dashboard` en `backend/app/main.py` | `tests/integration/run.sh`, caos | `dashboard.json` al ejecutar integración; `05-dashboard-replica.json` existente |
| Fragmentación horizontal | `fragmentation/horizontal/`, vista `patients_all` | `scripts/test-fragmentation-horizontal.sh` | Salida; archivo de integración después de ejecutar |
| Fragmentación vertical | `fragmentation/vertical/`, vista `patients_full` | `scripts/test-fragmentation-vertical.sh` | Salida; archivo de integración después de ejecutar |
| Separación de acceso | roles de fragmentación vertical | prueba de `public_role` | Salida del script vertical |
| Chaos Engineering | `scripts/chaos-replication.sh`, endpoint de escritura de caos | ejecución del mismo script | `docs/evidence/replication-chaos/01` a `09` |
| No exposición de secretos | separación de build args y variables backend | revisión de respuestas, logs y archivos estáticos en integración | `security.txt` después de ejecutar |
| Despliegue Atlas | `compose.atlas.yaml`, `docs/cloud/mongodb-atlas.md` | base temporal con `test-mongodb-atlas.sh` | `docs/evidence/final/mongodb-atlas-test.log` |

## 17. Auditoría de comandos del README

Se comprobó que todas las rutas de scripts citadas en `README.md` existen:
`bootstrap.sh`, pruebas MOR, XML/XSD, MongoDB, replicación, fragmentación,
integración, estado y caos. También existen los servicios Compose invocados:
`frontend`, `postgres-primary`, `postgres-replica`, `mongodb`, `backend`, los cuatro
fragmentos y ambos coordinadores. Los endpoints documentados están declarados
en FastAPI.

`docker compose config --services` valida la sintaxis y las referencias de
servicio sin arrancar contenedores. La ejecución funcional requiere un daemon
Docker activo y debe comprobarse con los comandos de las secciones 12 a 14.

## 18. Recuperación, diagnóstico y entrega

La recuperación de Primary/Replica, incluido el reset controlado que elimina
solo el volumen de Replica, está en
`docs/architecture/postgresql-primary-replica.md`. Los errores de Atlas y su
recuperación están en `docs/cloud/mongodb-atlas.md`. La guía cronometrada de
defensa está en `docs/defense/demo-guide.md`.

Para una reconstrucción total académica, confirmar primero que los datos pueden
perderse:

```bash
docker compose down -v --remove-orphans
docker compose up -d --build --wait --wait-timeout 240
```

Para crear el ZIP desde el directorio padre sin historial, secretos ni caché:

```bash
zip -r GlobalHealth_Unified_System.zip GlobalHealth_Unified_System \
  -x 'GlobalHealth_Unified_System/.git/*' \
     'GlobalHealth_Unified_System/.env' \
     'GlobalHealth_Unified_System/.env.*' \
     'GlobalHealth_Unified_System/**/__pycache__/*' \
     'GlobalHealth_Unified_System/**/*.pyc'
```

Comprobar que el listado no contiene `.git/`, `.env`, claves privadas ni URI
con credenciales. `.git` permanece intacto en el repositorio de trabajo.

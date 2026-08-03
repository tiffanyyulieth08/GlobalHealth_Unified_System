# Documentación final — GlobalHealth Unified System

## 1. Alcance y criterio de evidencia

Este documento describe únicamente lo implementado en el repositorio. Los comandos
de prueba indican cómo verificarlo, pero su presencia no equivale a una ejecución
exitosa. La evidencia de integración se genera al ejecutar
`scripts/test-all.sh`; actualmente `docs/evidence/integration/` solo contiene el
catálogo de archivos esperados. En cambio,
`docs/evidence/replication-chaos/` sí contiene artefactos de una ejecución previa.

## 2. Arquitectura completa

```text
Cliente HTTP
    |
    v
FastAPI :8000
    |-- escrituras SQL ------> PostgreSQL Primary --WAL asíncrono--> Replica
    |-- dashboard SQL ---------------------------------------------> Replica
    `-- telemetría ----------> MongoDB local o MongoDB Atlas

Coordinador vertical --postgres_fdw--> fragment-public
                     `---------------> fragment-financial

Coordinador horizontal --postgres_fdw--> fragment-north
                       `---------------> fragment-south
```

Todos los contenedores de datos se comunican por la red interna
`globalhealth-network`. El backend también pertenece a
`globalhealth-edge-network` y es el único servicio que publica un puerto al host.
Los datos persistentes usan volúmenes Docker. La configuración está en
`compose.yaml`; las credenciales se reciben por variables de entorno.

| Componente | Responsabilidad | Implementación |
| --- | --- | --- |
| FastAPI | Salud, dashboard, escritura de caos y API de telemetría | `backend/app/main.py`, `backend/app/routers/telemetry.py` |
| PostgreSQL Primary | Escrituras, MOR, XML y emisión WAL | `docker/postgres/primary/`, `database/postgres/` |
| PostgreSQL Replica | Hot standby y consultas del dashboard | `docker/postgres/replica/` |
| MongoDB | Pacientes, sesiones y mediciones de sensores | `database/mongodb/`, `backend/app/mongodb.py` |
| Fragmentación vertical | Separación de datos públicos y financieros | `database/postgres/fragmentation/vertical/` |
| Fragmentación horizontal | Separación de pacientes NORTH y SOUTH | `database/postgres/fragmentation/horizontal/` |
| Coordinadores | Reconstrucción mediante `postgres_fdw` | scripts `coordinator/01_setup.sh` |

### Flujo de una operación

Las escrituras SQL usan el pool creado desde `POSTGRES_WRITE_URL`, que apunta a
`postgres-primary`. El endpoint `/dashboard` usa exclusivamente el pool creado
desde `POSTGRES_READ_URL`, que apunta a `postgres-replica`. La API de telemetría
usa `MONGODB_URI` y `MONGODB_DB`. No existe conmutación automática ni promoción
de la réplica.

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

### Decisión recomendada

Para desarrollo académico y pruebas locales, el contenedor MongoDB evita costo
y dependencia de Internet. Para producción, Atlas aporta valor si el costo
mensual total de la configuración elegida es menor que operar guardias,
parches, respaldo, restauración, monitoreo y alta disponibilidad internamente.
No se fija un precio en este documento porque cambia por región y
configuración: debe obtenerse del estimador mostrado por Atlas y validarse con
una prueba de carga. Se deben presupuestar por separado cómputo, almacenamiento,
backups y transferencia.

Fuentes oficiales consultadas:

- https://www.mongodb.com/docs/atlas/billing/
- https://www.mongodb.com/docs/atlas/billing/cluster-configuration-costs/
- https://www.mongodb.com/docs/atlas/billing/data-transfer-costs/

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
`FRAGMENT_HORIZONTAL_FDW_PASSWORD`.

```bash
docker compose config
docker compose build
docker compose up -d --wait
docker compose ps
curl --fail http://localhost:8000/health
curl --fail http://localhost:8000/health/databases
curl --fail http://localhost:8000/api/mongodb/health
curl --fail http://localhost:8000/dashboard
```

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
mongosh "$MONGODB_URI" --quiet --file database/mongodb/01_collections.js
mongosh "$MONGODB_URI" --quiet --file database/mongodb/02_seed.js
mongosh "$MONGODB_URI" --quiet --file database/mongodb/03_operations.js
mongosh "$MONGODB_URI" --quiet --file database/mongodb/04_aggregations.js
```

En producción, la URI debe provenir de un gestor de secretos, no de Git ni de
la línea de comandos persistida por el shell.

## 13. Comandos de pruebas

Cada script devuelve un código distinto de cero cuando una aserción falla.

```bash
sh scripts/test-mor.sh
sh scripts/test-xml-xsd.sh
sh scripts/test-mongodb.sh
sh scripts/test-replication.sh
sh scripts/replication-status.sh
sh scripts/test-fragmentation-vertical.sh
sh scripts/test-fragmentation-horizontal.sh
sh scripts/test-fragmentation.sh
sh scripts/test-all.sh
```

La prueba integral usa por defecto el puerto `18080`, crea credenciales y un
proyecto Compose efímeros, guarda evidencia sanitizada y ejecuta
`docker compose down -v` al terminar. Para conservar el entorno:

```bash
KEEP_INTEGRATION_ENV=1 sh scripts/test-all.sh
```

Pruebas con clientes externos:

```bash
MOR_PSQL="psql -h localhost -U globalhealth" MOR_DB=globalhealth_mor_test sh scripts/test-mor.sh
XML_XSD_PSQL="psql -h localhost -U globalhealth" XML_XSD_DB=globalhealth_xml_xsd_test sh scripts/test-xml-xsd.sh
MONGODB_URI="$MONGODB_URI" MONGODB_DB=globalhealth_test sh scripts/test-mongodb.sh
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
8. guarda artefactos y usa un `trap` para restaurar Primary ante error.

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
| Arquitectura desplegable | `compose.yaml`, `backend/Dockerfile`, `docker/postgres/` | `docker compose config`, `docker compose ps` | Estado observado por el operador |
| MOR | `database/postgres/mor/01_types.sql` a `05_crud.sql` | `scripts/test-mor.sh`, `06_tests.sql` | Salida de consola; no se versiona actualmente |
| XML/XSD | `database/postgres/xml/`, `clinical-record-v1.xsd` | `scripts/test-xml-xsd.sh`, `04_tests.sql` | Salida de consola; no se versiona actualmente |
| MongoDB | `database/mongodb/01_collections.js` a `04_aggregations.js` | `scripts/test-mongodb.sh`, `05_tests.js` | Salida de consola; integración puede generar JSON |
| API MongoDB | `backend/app/routers/telemetry.py` | `tests/integration/run.sh` | `docs/evidence/integration/*.json` después de ejecutar |
| Primary/Replica | `compose.yaml`, `docker/postgres/primary/`, `docker/postgres/replica/` | `scripts/test-replication.sh` | Salida de consola |
| Lecturas desde Replica | endpoint `/dashboard` en `backend/app/main.py` | `tests/integration/run.sh`, caos | `dashboard.json` al ejecutar integración; `05-dashboard-replica.json` existente |
| Fragmentación horizontal | `fragmentation/horizontal/`, vista `patients_all` | `scripts/test-fragmentation-horizontal.sh` | Salida; archivo de integración después de ejecutar |
| Fragmentación vertical | `fragmentation/vertical/`, vista `patients_full` | `scripts/test-fragmentation-vertical.sh` | Salida; archivo de integración después de ejecutar |
| Separación de acceso | roles de fragmentación vertical | prueba de `public_role` | Salida del script vertical |
| Chaos Engineering | `scripts/chaos-replication.sh`, endpoint de escritura de caos | ejecución del mismo script | `docs/evidence/replication-chaos/01` a `09` |
| No exposición de secretos | variables de entorno y revisión de respuestas/logs | bloque de seguridad de `tests/integration/run.sh` | `security.txt` después de ejecutar |
| Despliegue Atlas | `docs/cloud/mongodb-atlas.md` | base temporal con `test-mongodb.sh` | Salida del operador |

## 17. Auditoría de comandos del README

Se comprobó que todas las rutas de scripts citadas en `README.md` existen:
`bootstrap.sh`, pruebas MOR, XML/XSD, MongoDB, replicación, fragmentación,
integración, estado y caos. También existen los servicios Compose invocados:
`postgres-primary`, `postgres-replica`, `mongodb`, `backend`, los cuatro
fragmentos y ambos coordinadores. Los endpoints documentados están declarados
en FastAPI.

`docker compose config --services` valida la sintaxis y las referencias de
servicio sin arrancar contenedores. La ejecución funcional requiere un daemon
Docker activo y debe comprobarse con los comandos de las secciones 12 a 14.

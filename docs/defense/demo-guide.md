# Guía de defensa — demostración de 15 minutos

## Preparación

Ejecutar antes de la exposición:

```sh
cp .env.example .env
docker compose down -v --remove-orphans
docker compose up -d --build --wait --wait-timeout 240
sh scripts/test-all.sh
```

Usar contraseñas locales no compartidas y no mostrar `.env`. Para Atlas,
exportar `MONGODB_URI` desde un gestor de secretos y ejecutar previamente
`sh scripts/test-mongodb-atlas.sh`. Si esa prueba no produce `PASS`, declarar
Atlas como bloqueo; no simular el resultado.

## 0:00–1:00 — Arquitectura

Mostrar `compose.yaml` y explicar: FastAPI es el único servicio expuesto;
PostgreSQL separa Primary de Replica; MongoDB funciona local o en Atlas; los
cuatro fragmentos se consultan mediante dos coordinadores `postgres_fdw`.

```sh
docker compose ps
curl --fail http://localhost:8000/health/databases
```

Resultado esperado: servicios `healthy`; JSON con `status=healthy`,
Primary `in_recovery=false` y Replica `in_recovery=true`.

## 1:00–3:00 — MOR

```sh
sh scripts/test-mor.sh
```

Mostrar `database/postgres/mor/01_types.sql` y
`database/postgres/mor/02_tables.sql`. Explicar tipos compuestos, tabla tipada,
herencia, composición y arreglos. Resultado esperado:
`All MOR tests passed.`

## 3:00–5:00 — XML/XSD

```sh
sh scripts/test-xml-xsd.sh
```

Mostrar `clinical-record-v1.xsd` y el trigger de validación en
`02_clinical_records.sql`. Explicar la diferencia entre XML bien formado y
válido según XSD. Resultado esperado:
`All XML/XSD tests passed.`

## 5:00–7:00 — MongoDB local y Atlas

```sh
sh scripts/test-mongodb.sh
curl --fail http://localhost:8000/api/mongodb/health
```

Resultado local esperado: `All MongoDB scripts passed.` y JSON sanitizado con
`provider=local`.

Sin mostrar la URI:

```sh
MONGODB_URI="$MONGODB_URI" sh scripts/test-mongodb-atlas.sh
```

Resultado esperado con Atlas real:
`PASS: validación real de MongoDB Atlas completada sin exponer la URI.` La
demostración incluye CRUD, agregación, `$lookup` y salud del backend en una
base temporal que se elimina al finalizar.

## 7:00–9:00 — Fragmentación

```sh
sh scripts/test-fragmentation-horizontal.sh
sh scripts/test-fragmentation-vertical.sh
```

Resultado esperado: horizontal termina sin `patient_id` duplicados y
reconstruye diez filas mediante `UNION ALL`; vertical termina sin huérfanos,
reconstruye seis pacientes mediante `JOIN` y niega al rol público el fragmento
financiero.

## 9:00–13:00 — Replicación y caos

```sh
sh scripts/replication-status.sh
sh scripts/chaos-replication.sh
```

Narrar los resultados mientras corre el experimento:

1. lectura desde Replica con Primary activo;
2. dato escrito en Primary y observado en Replica;
3. Primary detenido sin borrar volúmenes;
4. dashboard HTTP 200 servido por Replica;
5. escritura rechazada con HTTP 503;
6. Primary reiniciado y streaming recuperado;
7. escritura nueva HTTP 201 y confirmación en Replica.

Resultado esperado:
`All replication chaos checks passed.` No existe promoción ni failover
automático: la Replica permanece en recovery.

## 13:00–15:00 — CAP, BASE, costos y cierre

CAP: durante la caída se conserva disponibilidad de lectura desde una copia
potencialmente atrasada y se rechazan escrituras. BASE describe la convergencia
asíncrona Primary/Replica; las transacciones locales siguen siendo ACID.

Mostrar la tabla cuantitativa de `docs/final-documentation.md` y aclarar sus
supuestos. Cerrar con:

```sh
git diff --check
git status --short
```

Resultado esperado: `git diff --check` sin salida. `git status --short` debe
mostrar únicamente los cambios explicados de la entrega. El veredicto final se
consulta en `docs/evidence/final/rubric-matrix.md`.

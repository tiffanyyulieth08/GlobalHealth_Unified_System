# PostgreSQL Primary/Replica

## Arquitectura

`postgres-primary` acepta escrituras y genera registros WAL. Durante el primer
inicio, `postgres-replica` ejecuta `pg_basebackup`, crea `standby.signal` y se
mantiene en hot standby para atender lecturas.

El backend separa las conexiones:

| Variable | Servicio | Uso |
| --- | --- | --- |
| `POSTGRES_WRITE_URL` | `postgres-primary` | Escrituras y operaciones transaccionales |
| `POSTGRES_READ_URL` | `postgres-replica` | Dashboard y consultas de lectura |

El endpoint `GET /dashboard` utiliza exclusivamente `read_pool`, creado desde
`POSTGRES_READ_URL`. La respuesta identifica la fuente como `replica` y reporta
`in_recovery`, base observada, tamaño y conexiones activas.

## Configuración

El primario usa:

- `wal_level = replica`;
- hasta 10 procesos `wal_sender`;
- retención de 256 MB de WAL;
- autenticación SCRAM para conexiones y replicación.

El usuario definido por `POSTGRES_REPLICATION_USER` tiene únicamente
`REPLICATION LOGIN`. Su contraseña se recibe mediante
`POSTGRES_REPLICATION_PASSWORD`; no se almacena una credencial real en Git.

## Inicialización

```sh
cp .env.example .env
docker compose up -d --build --wait postgres-primary postgres-replica
```

Los scripts de inicialización de PostgreSQL solo se ejecutan sobre volúmenes
vacíos. Si se migra un ambiente local creado antes de habilitar replicación,
respalda los datos y recrea los volúmenes de forma controlada antes de iniciar
la nueva topología.

## Verificación

Ejecuta la prueba automatizada:

```sh
sh scripts/test-replication.sh
```

La prueba comprueba:

1. `pg_is_in_recovery()` es `false` en Primary.
2. `pg_is_in_recovery()` es `true` en Replica.
3. Un registro temporal escrito en Primary aparece en Replica.

Para inspeccionar emisor y receptor WAL:

```sh
sh scripts/replication-status.sh
```

FastAPI expone `GET /health/databases`, que responde correctamente solo cuando
ambos pools están disponibles y cada servidor cumple el rol esperado.

## Operación

- Envía escrituras únicamente a `POSTGRES_WRITE_URL`.
- Usa `POSTGRES_READ_URL` solo para consultas tolerantes al retraso de réplica.
- Supervisa `pg_stat_replication` y `pg_stat_wal_receiver`.
- Conserva copias de seguridad independientes de la réplica.
- Rota las credenciales y mantenlas fuera del repositorio.

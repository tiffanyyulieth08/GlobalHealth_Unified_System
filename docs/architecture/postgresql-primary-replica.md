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

## Separación Primary/Replica y comportamiento ante fallos

La separación es explícita y no existe descubrimiento dinámico:

- `write_pool` solo usa `POSTGRES_WRITE_URL`;
- `read_pool` y `/dashboard` solo usan `POSTGRES_READ_URL`;
- la Replica permanece en hot standby y rechaza escrituras;
- detener Primary no promueve la Replica;
- durante la caída, `/dashboard` puede seguir respondiendo, pero las escrituras
  controladas responden HTTP 503.

`scripts/chaos-replication.sh` detiene Primary sin eliminar datos, comprueba
lectura y rechazo de escritura, lo reinicia, espera el streaming, realiza una
escritura nueva y la confirma en Replica. Un `trap` intenta recuperar Primary
si la ejecución se interrumpe.

## Reset controlado de Replica

Este procedimiento destruye únicamente el volumen de Replica. Primary debe
estar saludable y conservar la copia autoritativa:

```sh
docker compose up -d --wait postgres-primary
docker compose stop postgres-replica
docker compose rm -f postgres-replica
docker volume ls --format '{{.Name}}' | grep 'postgres-replica-data$'
docker volume rm NOMBRE_EXACTO_CONFIRMADO
docker compose up -d --wait --wait-timeout 240 postgres-replica
sh scripts/test-replication.sh
```

Antes de `docker volume rm`, verificar visualmente que el nombre termina en
`postgres-replica-data` y pertenece al proyecto Compose actual. No eliminar
`postgres-primary-data`. La nueva Replica ejecuta `pg_basebackup` desde
Primary. Si hay datos únicos en la Replica —situación no prevista por el
diseño— detenerse y respaldarlos antes del reset.

Para reiniciar todo el ambiente académico desde cero, después de confirmar que
los datos pueden perderse:

```sh
docker compose down -v --remove-orphans
docker compose up -d --build --wait --wait-timeout 240
```

## Recuperación y errores frecuentes

| Síntoma | Comprobación | Recuperación |
| --- | --- | --- |
| Replica no entra en `streaming` | `docker compose logs postgres-replica` y `sh scripts/replication-status.sh` | Confirmar Primary saludable y credenciales de replicación; si el volumen quedó incompatible, aplicar el reset controlado de Replica. |
| Primary inicia pero Replica conserva credenciales antiguas | Comparar variables activas sin imprimir sus valores | Recrear solo el volumen de Replica para repetir `pg_basebackup`. |
| `/health/databases` responde 503 | Revisar el rol de ambos nodos con `pg_is_in_recovery()` | Recuperar el nodo incorrecto; no intercambiar las URL de lectura y escritura. |
| Escritura enviada a Replica | Revisar `POSTGRES_WRITE_URL` | Apuntar exclusivamente a `postgres-primary`; no desactivar hot standby. |
| WAL crece sin límite | Revisar estado del receptor y uso de disco | Recuperar o reconstruir Replica; la retención configurada no sustituye monitoreo. |

La Replica no es un backup: replica también borrados y errores lógicos. La
recuperación ante pérdida de Primary requiere una estrategia de backup/restore
o promoción manual fuera del alcance implementado.

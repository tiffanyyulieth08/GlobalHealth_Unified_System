# Despliegue de telemetría en MongoDB Atlas

## Configuración

La aplicación acepta exactamente dos proveedores:

```dotenv
# Local
MONGODB_PROVIDER=local
MONGODB_URI=mongodb://mongodb:27017/globalhealth
MONGODB_DB=globalhealth

# Atlas
MONGODB_PROVIDER=atlas
MONGODB_URI=mongodb+srv://<username>:<password>@<cluster>/globalhealth
MONGODB_DB=globalhealth
```

`.env` está ignorado. La URI real debe permanecer en `.env`, en variables del
entorno o en un gestor de secretos; nunca se versiona. El backend no registra
la URI y `GET /api/mongodb/health` solo responde `status`, `provider` y
`database`.

En Atlas se debe crear un usuario con privilegio mínimo sobre la base de la
aplicación y una lista de acceso IP restrictiva. No se debe autorizar
`0.0.0.0/0` en producción. Las URI `mongodb+srv` usan TLS explícitamente en el
cliente.

## Modo local

El archivo principal contiene MongoDB local. Inicia todos los servicios para
que MongoDB esté disponible antes de evaluar el backend:

```sh
docker compose up -d --build --wait
curl http://localhost:8000/api/mongodb/health
```

Respuesta esperada:

```json
{"status":"healthy","provider":"local","database":"globalhealth"}
```

## Modo Atlas

`compose.atlas.yaml` es un override pequeño que cambia únicamente el proveedor
y exige una URI. Al dirigir `up` al servicio `backend`, MongoDB local no es una
dependencia y no se inicia:

```sh
export MONGODB_URI='mongodb+srv://<username>:<password>@<cluster>/globalhealth'
docker compose -f compose.yaml -f compose.atlas.yaml up -d --build --wait backend
curl http://localhost:8000/api/mongodb/health
```

No se debe usar `docker compose up` sin indicar `backend` en este modo, porque
eso solicitaría todos los servicios definidos, incluido el MongoDB local.

## Validación real y segura

El validador requiere `docker`, `mongosh`, `curl` y `python`. Exige una URI SRV,
crea una base cuyo nombre comienza con
`globalhealth_atlas_validation_`, crea colecciones e índices, prueba inserción,
actualización, consulta, agregación y `$lookup`, inicia FastAPI en modo Atlas y
consulta su salud. Al salir elimina solamente esa base temporal y el proyecto
Compose efímero.

```sh
MONGODB_URI="$MONGODB_URI" sh scripts/test-mongodb-atlas.sh
```

El script no imprime la URI, el host ni el usuario. Los errores de herramientas
se capturan y se presenta únicamente una etapa sanitizada. Si no existe una URI
real, termina con:

```text
BLOCKED: MONGODB_URI de Atlas no proporcionada.
```

Una salida `PASS` solo constituye evidencia si el comando fue ejecutado con una
URI Atlas real. No hay una ejecución Atlas exitosa versionada en este
repositorio.

## API para la defensa

- `GET /api/sensor-logs?recordedFrom=...&recordedTo=...&limit=100` filtra por
  rango inclusivo y limita el resultado a un máximo de 500.
- `GET /api/telemetry/summary?patientId=...&limit=50` agrupa por paciente,
  sensor y unidad, calcula conteo, mínimo, máximo y promedio, y usa `$lookup`
  para incluir el nombre del paciente. El máximo es 100 grupos.
- `GET /api/patients/{patientId}/telemetry` demuestra la jerarquía con límites
  configurables `sessionLimit` y `logsPerSession`.

## Seguridad operativa

- Usa usuarios diferentes por ambiente, privilegio mínimo y rotación.
- Conserva `APP_ENV=production` y `APP_DEBUG=false` en producción.
- Configura alertas, copias de seguridad y retención de telemetría.
- No registres URIs ni documentos clínicos.
- CORS no está habilitado porque este alcance no incluye un frontend. Si se
  añade uno, se deben declarar orígenes concretos; nunca un comodín productivo.

## Referencias oficiales

- [Conectar a un clúster de Atlas](https://www.mongodb.com/docs/atlas/connect-to-database-deployment/)
- [Configurar usuarios de base de datos](https://www.mongodb.com/docs/atlas/security-add-mongodb-users/)
- [Administrar la lista de acceso IP](https://www.mongodb.com/docs/atlas/security/add-ip-address-to-list/)

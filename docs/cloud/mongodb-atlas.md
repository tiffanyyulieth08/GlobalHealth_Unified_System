# Despliegue de telemetría en MongoDB Atlas

## 1. Crear el clúster

1. Crea un proyecto y un clúster en MongoDB Atlas.
2. En **Database Access**, crea un usuario con permisos `readWrite` únicamente sobre la base `globalhealth`.
3. En **Network Access**, autoriza solo las direcciones IP del backend y del equipo de administración. Evita `0.0.0.0/0` en producción.
4. En **Connect > Drivers**, copia la cadena SRV. No la guardes en Git.

## 2. Configurar variables

Copia `.env.example` a `.env` y establece valores locales:

```dotenv
MONGODB_URI=mongodb+srv://USUARIO:CONTRASENA@CLUSTER/globalhealth?retryWrites=true&w=majority
MONGODB_DB=globalhealth
```

El ejemplo contiene marcadores, no credenciales reales. Si la contraseña incluye caracteres reservados, codifícala como componente de URL. En producción, almacena `MONGODB_URI` en el gestor de secretos de la plataforma.

## 3. Crear colecciones, índices y datos

Instala `mongosh`, exporta las variables sin imprimir la URI y ejecuta:

```sh
mongosh "$MONGODB_URI" --quiet --file database/mongodb/01_collections.js
mongosh "$MONGODB_URI" --quiet --file database/mongodb/02_seed.js
mongosh "$MONGODB_URI" --quiet --file database/mongodb/03_operations.js
mongosh "$MONGODB_URI" --quiet --file database/mongodb/04_aggregations.js
```

`01_collections.js` es idempotente. La semilla y la demostración eliminan únicamente documentos cuyos identificadores comienzan con `SEED-` y `DEMO-`, respectivamente.

## 4. Validar en una base temporal

El script de prueba usa `globalhealth_test` por defecto y elimina esa base al terminar:

```sh
MONGODB_URI="$MONGODB_URI" MONGODB_DB=globalhealth_test ./scripts/test-mongodb.sh
```

No apuntes la prueba a una base que contenga información que debas conservar.

## 5. Ejecutar FastAPI

La aplicación lee exclusivamente `MONGODB_URI` y `MONGODB_DB`; no hay credenciales en el código. Instala dependencias y ejecuta:

```sh
python -m pip install -r backend/requirements.txt
uvicorn app.main:app --app-dir backend --reload
```

Verifica la conexión con `GET /api/mongodb/health`. Los endpoints principales permiten crear y listar pacientes, crear y completar sesiones, insertar y filtrar logs, y consultar `GET /api/patients/{patientId}/telemetry` para el pipeline paciente → sesiones → logs.

## 6. Recomendaciones operativas

- Usa un usuario distinto por ambiente y aplica privilegio mínimo.
- Habilita alertas, copias de seguridad y eliminación programada de logs según la política clínica.
- Mantén TLS habilitado y rota las credenciales periódicamente.
- No registres la URI ni documentos que contengan datos médicos.
- Revisa en **Performance Advisor** los índices después de observar carga real.

## Referencias oficiales

- [Conectar a un clúster de Atlas](https://www.mongodb.com/docs/atlas/connect-to-database-deployment/)
- [Configurar usuarios de base de datos](https://www.mongodb.com/docs/atlas/security-add-mongodb-users/)
- [Administrar la lista de acceso IP](https://www.mongodb.com/docs/atlas/security/add-ip-address-to-list/)

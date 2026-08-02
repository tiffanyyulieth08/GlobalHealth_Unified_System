# Evidencias de integración

La ejecución de `sh scripts/test-all.sh` guarda en este directorio evidencias
sanitizadas del flujo completo.

| Archivo | Verificación |
| --- | --- |
| `postgresql.txt` | Médico creado en Primary, XML válido insertado y XML inválido rechazado |
| `mongodb-setup.txt` | Colecciones e índices de telemetría preparados |
| `patient.json` | Paciente creado en MongoDB |
| `session.json` | Sesión asociada al paciente |
| `sensor-log-1.json`, `sensor-log-2.json` | Lecturas de sensores insertadas |
| `lookup.json` | Resultado del `$lookup` paciente → sesiones → logs |
| `dashboard.json` | Dashboard con `source=replica` e `in_recovery=true` |
| `fragmentation-horizontal.txt` | Reconstrucción mediante `UNION ALL` |
| `fragmentation-vertical.txt` | Reconstrucción mediante `JOIN` |
| `backend.txt`, `security.txt` | Logs revisados y ausencia de credenciales |

Las credenciales usadas por la prueba son efímeras e incluyen el identificador
de la ejecución. El control de seguridad busca tanto sus valores exactos como
campos o URI con formato de credencial. Si se detecta una coincidencia, la
prueba termina con error y no declara éxito.

Los archivos reflejan la ejecución más reciente. No debe copiarse aquí el
archivo `.env` ni salida sin sanitizar de `docker compose config`.

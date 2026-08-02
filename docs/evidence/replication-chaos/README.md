# Evidencias de caos de replicación

`sh scripts/chaos-replication.sh` guarda aquí la evidencia de la demostración
más reciente.

| Archivo | Evidencia |
| --- | --- |
| `01-initial-health.json`, `01-initial-health-http.txt` | Primary y Replica saludables |
| `02-primary-insert.txt` | Identificador insertado en Primary |
| `03-replica-observation.txt` | Dato observado en Replica |
| `04-primary-stop.txt` | Detención controlada de Primary |
| `05-dashboard-replica.json`, `05-dashboard-http.txt` | Dashboard servido con HTTP 200 desde Replica durante la caída |
| `06-rejected-write.json`, `06-rejected-write-http.txt` | Escritura rechazada con HTTP 503 |
| `07-primary-start.txt` | Reinicio de Primary |
| `08-primary-recovery.txt` | Primary fuera de recovery y nuevamente disponible |
| `09-streaming-restored.txt` | Streaming confirmado en ambos nodos |
| `99-emergency-restoration.txt` | Recuperación ejecutada por el `trap` si la prueba falla durante la caída |

El script no ejecuta promoción, `docker compose down` ni eliminación de
volúmenes. Un `trap` de salida reinicia Primary si ocurre un error después de
detenerlo.

# Guía manual de verificación desde el navegador

Fecha objetivo de defensa: **17/08/2026**

URLs predeterminadas: **SPA `http://localhost:3000`** y **API/Swagger `http://localhost:8000/docs`**

Esta guía está construida a partir del enunciado `Proyecto_Final_Avanzado_BBDD.docx` y del código integrado actual. Todos los pasos funcionales se hacen en el navegador. No se presupone que una pantalla existe solo porque hay una prueba automatizada.

## Antes de empezar: cómo usar la API sin otra herramienta

Para una URL `GET`, ábrela directamente en una pestaña nueva. El navegador mostrará el JSON.

Para `POST`, `PATCH`, `PUT` o `DELETE`, abre `http://localhost:8000/docs`, despliega el endpoint indicado, pulsa **Try it out**, completa los parámetros o el cuerpo JSON y pulsa **Execute**. Comprueba **Code** y **Response body**. Swagger es parte de FastAPI y se usa dentro del navegador; no necesitas `curl`, Postman ni una consola.

No abras ni proyectes `.env`, la URI de Atlas, contraseñas o tokens.

## Qué exige el enunciado y qué materializa el sistema

| Requerimiento exigible | Ruta SPA | API que lo materializa | Alcance visual real |
| --- | --- | --- | --- |
| MOR: tipos compuestos, atributos complejos, funciones sobre tipos, composición/agregación, herencia, tabla tipada, arreglos y CRUD | `/staff` | `/api/mor/doctors`, `/api/mor/clinics` y subrutas de `specialties`, `phones`, `equipments` | La SPA hace CRUD de médicos y arreglos de especialidades/teléfonos; consulta clínicas y equipos. El CRUD de clínicas/equipos existe solo en API. La herencia y los tipos se demuestran por el resultado, pero su definición es interna a PostgreSQL. |
| XML: columna XML, registro/actualización/borrado de XSD, validación estricta, CRUD de documentos, extracción y cambio de nodos | `/clinical-records` | `/api/xml/schemas`, `/api/xml/records`, `/api/xml/records/relational`, `/api/xml/records/{id}/nodes` y `/content` | La SPA hace CRUD de documentos y operaciones XPath. El CRUD del registro XSD existe solo en API. |
| MongoDB: Paciente → Sesión → Logs, identificadores únicos, inserciones, actualizaciones, filtros, límites, agregación y `$lookup` | `/telemetry` | `/api/patients`, `/api/sessions`, `/api/sensor-logs`, `/api/telemetry/summary`, `/api/patients/{id}/telemetry` | La SPA es de consulta. Las escrituras existen en API. No hay borrado API de pacientes/sesiones/logs, por lo que esta guía evita crear basura permanente. |
| Replicación Primary/Replica en contenedores separados; escritura en Primary y dashboard leído desde Replica | `/` | `/health/databases`, `/dashboard`, `/chaos/replication/write`, `/api/infrastructure/status` | La SPA observa roles, flujo WAL y continuidad de lectura. No existe botón ni endpoint para detener un contenedor. |
| Fragmentación horizontal NORTH/SOUTH y reconstrucción global | `/distribution` | `/api/fragmentation/horizontal`, `/api/fragmentation/horizontal/summary` | Consulta visual y API solamente. La función de inserción y sus reglas existen en SQL, pero no están expuestas por HTTP. |
| Fragmentación vertical pública/financiera con la misma PK y reconstrucción por `JOIN` | `/distribution` | `/api/fragmentation/vertical`, `/api/fragmentation/vertical/summary` | Consulta visual y API solamente. |
| Nube: MongoDB Atlas real, conexión segura y evaluación cuantitativa costo/beneficio | `/` y `/telemetry` | `/api/mongodb/health`, `/api/infrastructure/status` y API de telemetría | El Dashboard muestra `Provider: atlas` sin revelar la URI. La tabla de costos no está en la SPA; está en `docs/final-documentation.md`. |

## Límite que debes declarar con honestidad

La demostración completa de parada controlada pedida por el enunciado **no puede iniciarse solo desde el navegador**. El repositorio deliberadamente no expone una API que controle Docker. Para el ensayo browser-only puedes comprobar toda la topología activa. Para el caos en vivo, otra persona o tú fuera de este recorrido debe detener y luego iniciar únicamente `postgres-primary`; desde el navegador haces todas las observaciones descritas en la sección de Replicación. No digas que pulsar **Actualizar** detiene el Primary.

---

# 1. Dashboard

## Qué se está demostrando

“Este panel integra la salud de PostgreSQL Primary, PostgreSQL Replica y MongoDB, y sus métricas se consultan explícitamente desde la Replica.”

## Pre-condición

- La SPA y la API responden en los puertos 3000 y 8000.
- Los 11 servicios del perfil local están activos y saludables: MongoDB, Primary, Replica, cuatro fragmentos, dos coordinadores, backend y frontend.
- Si vas a afirmar nube real, el backend debe estar iniciado con proveedor Atlas y credencial vigente. `provider: local` no demuestra nube.

## Pasos en la interfaz

1. Abre `http://localhost:3000/`.
2. Confirma el encabezado **Buenos días, equipo** y el bloque **PLATAFORMA HEALTHY**.
3. Lee las tres tarjetas. Debes ver:
   - **PostgreSQL Primary**, `Healthy`, **Nodo de escritura** y **Aceptando escrituras**.
   - **PostgreSQL Replica**, `Healthy`, **Nodo de lectura** y **En modo recovery**.
   - **MongoDB**, `Healthy`, el nombre de la base y `Provider: local` o `Provider: atlas` según el perfil realmente activo.
4. En **Flujo de replicación**, señala **Primary → WAL → Replica** y la etiqueta **Consultas servidas por Replica**.
5. En **Métricas del dashboard**, confirma la insignia **Fuente: Replica**, el nombre de base, almacenamiento, conexiones activas y hora de observación.
6. Pulsa **Actualizar**. Debe reaparecer la información sin navegar a otra pantalla y la hora observada debe actualizarse.

## Verificación cruzada por API

1. Abre `http://localhost:8000/dashboard`. Debes ver `"source":"replica"` e `"in_recovery":true`.
2. Abre `http://localhost:8000/health/databases`. Debes ver `"status":"healthy"`, Primary con `"in_recovery":false` y Replica con `"in_recovery":true`.
3. Abre `http://localhost:8000/api/infrastructure/status`. Debe identificar los tres componentes como `healthy`.
4. Para nube, abre `http://localhost:8000/api/mongodb/health`. Solo si responde `"provider":"atlas"` puedes decir que esa ejecución consume Atlas. La respuesta nunca debe mostrar la cadena de conexión.

## Caso de error esperado

Sin detener servicios, abre Swagger, despliega `POST /chaos/replication/write`, pulsa **Try it out** y luego **Execute** dejando sin valor el parámetro obligatorio `probe_id`. Debe responder **422** y señalar que falta `probe_id`; no modifica datos.

Durante el caos real, con Primary detenido externamente, pulsa **Actualizar**. Debes ver **PostgreSQL Primary Offline**, **Escrituras no disponibles**, **PostgreSQL Replica Healthy** y plataforma **Degraded**, pero las métricas deben seguir visibles desde Replica. El `POST /chaos/replication/write` con `probe_id=DEMO-20260817-DOWN` debe responder **503** con `"status":"unavailable"` y `"detail":"PostgreSQL Primary is unavailable"`.

## Qué hacer si no ves lo esperado

- Si toda la página muestra error, prueba `http://localhost:8000/dashboard`: la Replica o la API no están disponibles.
- Si Primary y Replica aparecen invertidos, revisa la configuración activa de las conexiones de lectura/escritura; el código espera Primary fuera de recovery y Replica dentro de recovery.
- Si MongoDB aparece `Offline`, abre `/api/mongodb/health`: las causas más probables son datos de conexión, lista IP/TLS de Atlas o MongoDB local no disponible.

---

# 2. MOR / Personal clínico

## Qué se está demostrando

“Este módulo usa el modelo objeto-relacional: `doctor` hereda de `employee`; clínicas, direcciones, teléfonos y equipos usan tipos compuestos; especialidades, teléfonos y equipos son arreglos; las operaciones de la SPA escriben en Primary.”

## Pre-condición

- Primary, backend y frontend saludables.
- Deben existir los datos semilla **Ana Solano / MED-1234** y **Luis Vargas / MED-5678**.
- Usa siempre nombres con `DEMO-20260817`. Registrar un médico crea una fila real persistente. Al final se eliminará, y esa eliminación es permanente.

## Pasos en la interfaz

1. En el menú, pulsa **Personal**. Debes ver **Directorio clínico**, **Médicos** y `2 profesionales registrados` si el volumen está recién sembrado.
2. En **Buscar por nombre, licencia o especialidad**, escribe `MED-1234`. Debe quedar **Ana Solano** con la etiqueta **Cardiologia**.
3. Pulsa la fila de Ana. Debes ver correo, clínica **GlobalHealth San Jose**, fecha, salario; en **Clínica y equipos**, Siemens MAGNETOM Vida y GE HealthCare Revolution; en **Especialidades**, Cardiologia y Medicina Interna; y dos teléfonos.
4. Borra la búsqueda y pulsa **Registrar médico**. Completa exactamente:
   - **Nombre:** `Demo`
   - **Apellidos:** `Defensa 20260817`
   - **Correo electrónico:** `demo.defensa.20260817@globalhealth.test`
   - **Especialidad principal:** `Medicina de Emergencias`
   - **Licencia profesional:** `DEMO-20260817`
   - **Fecha de ingreso:** `2026-08-17`
   - **Salario (USD):** `1000`
   - **Clínica:** `GlobalHealth San Jose`
5. Pulsa **Registrar**. Debes ver **Médico registrado correctamente.**, el contador debe aumentar y debe aparecer la nueva fila.
6. Selecciona la fila nueva. En **Especialidades**, escribe `Medicina de Desastres` en **Nueva especialidad** y pulsa **Agregar**. Debes ver la nueva ficha y **Especialidad agregada.**
7. En **Teléfonos**, deja `+506`, escribe `7000-2026`, elige **Móvil** y pulsa el **Agregar** de esa sección. Debes ver `Móvil: +506 7000-2026` y **Teléfono agregado.**
8. Pulsa **Editar**, cambia **Apellidos** a `Defensa Ensayo 20260817` y pulsa **Guardar cambios**. Debes ver **Datos del médico actualizados.**

## Verificación cruzada por API

1. Abre `http://localhost:8000/api/mor/doctors` y busca en la página `DEMO-20260817`.
2. En ese objeto confirma `specialties` con `Medicina de Desastres`, `phone_numbers` con `7000-2026` y `clinic_id: 1`. Anota su `id` como `ID_DEMO`.
3. Abre `http://localhost:8000/api/mor/doctors/ID_DEMO`; debe devolver el mismo perfil editado.
4. Abre `http://localhost:8000/api/mor/clinics/1`; el objeto contiene `address` compuesto y el arreglo `equipments` mostrado por la UI.

## Caso de error esperado

1. Pulsa **Registrar médico** nuevamente.
2. Usa nombre `Error`, apellidos `Duplicado`, correo único `error.duplicado.20260817@globalhealth.test`, especialidad `Prueba` y licencia existente `MED-1234`.
3. Pulsa **Registrar**. El modal permanece abierto porque la petición fue rechazada. Ciérralo con el botón **Cerrar** de la esquina superior; entonces debes ver en la página el aviso rojo exacto **Integrity conflict: duplicate value**. No debe aparecer una fila nueva. Este detalle importa: el código coloca el aviso fuera del modal, no dentro de él.

Como caso de validación del navegador, dejar vacío **Nombre**, **Apellidos**, **Correo electrónico**, **Especialidad principal** o **Licencia profesional** impide enviar el formulario porque esos campos son obligatorios. El texto nativo puede variar según el idioma del navegador.

## Limpieza advertida

Selecciona el médico `DEMO-20260817`, pulsa **Eliminar** y acepta **¿Eliminar a Demo Defensa Ensayo 20260817? Esta acción no se puede deshacer.** Debes ver **Médico eliminado.** Esta eliminación es permanente, pero solo afecta el dato de práctica claramente identificado.

## Qué hacer si no ves lo esperado

- Si la lista no carga, abre `/api/mor/doctors`; un 503 apunta a Primary o al pool de escritura, no a la búsqueda visual.
- Si las clínicas no aparecen en el selector, revisa `/api/mor/clinics`; sin semillas todavía puedes registrar sin clínica, pero no demostrar composición/equipos.
- Si el alta devuelve conflicto antes de probar el duplicado, quedó un `DEMO-20260817` de un ensayo anterior; localízalo y elimínalo conscientemente antes de repetir.

---

# 3. XML / Expedientes clínicos

## Qué se está demostrando

“PostgreSQL almacena un documento XML real y decide su validez contra el XSD registrado; la interfaz permite CRUD del documento, extracción XPath, reemplazo y borrado interno con revalidación.”

## Pre-condición

- Primary, backend y frontend saludables.
- `/api/xml/schemas` debe incluir `clinical-record-v1`, versión `1.0`, namespace `https://globalhealth.example/xml/clinical-record/v1`.
- Crear el expediente siguiente inserta una fila real. Está identificada como demo y se eliminará al final.

## Pasos en la interfaz

1. En el menú, pulsa **Expedientes** y luego **Nuevo expediente**.
2. En **Esquema XSD**, elige `clinical-record-v1 · v1.0`.
3. Sustituye todo **Documento XML** por:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<clinicalRecord xmlns="https://globalhealth.example/xml/clinical-record/v1" version="1.0">
  <patient>
    <id>PAT-260817</id>
    <fullName>Paciente Demo Defensa</fullName>
    <birthDate>1990-08-17</birthDate>
  </patient>
  <physician>
    <license>MED-26081</license>
    <fullName>Doctora Demo Defensa</fullName>
  </physician>
  <recordDate>2026-08-17T09:00:00-06:00</recordDate>
  <diagnosis code="Z00.0" severity="low">Evaluación general de demostración</diagnosis>
  <notes>DEMO-20260817; eliminar después de practicar.</notes>
</clinicalRecord>
```

4. Pulsa **Validar y guardar**. Debes ver **Expediente creado y validado por PostgreSQL.**, una fila **Expediente #…** con **XML válido**, y en el detalle el banner **XML válido y conforme al XSD**. Anota el número como `ID_XML`.
5. Abre **Sección técnica**. Debes ver **XSD aplicado**, versión, namespace y **Datos extraídos mediante XMLTABLE**, incluidos identificador/nombre del paciente, licencia/nombre del médico, fecha, código y texto del diagnóstico.
6. En **Operaciones internas seguras**, completa:
   - **Expresión XPath:** `/gh:clinicalRecord/gh:diagnosis`
   - **Namespaces (JSON):** `{"gh":"https://globalhealth.example/xml/clinical-record/v1"}`
7. Pulsa **Consultar XPath**. Debes ver `1 resultado(s) XPath` y el nodo `<diagnosis ...>`.
8. En **Nuevo contenido**, escribe `Evaluación general actualizada en defensa` y pulsa **Reemplazar contenido**. Debes ver **Contenido interno reemplazado y revalidado por el backend.** y el XML con el texto nuevo.
9. Pulsa **Editar XML**, cambia el contenido de `<notes>` a `DEMO-20260817 actualizado por CRUD completo.`, y pulsa **Validar y guardar**. Debes ver **Expediente actualizado y validado por PostgreSQL.**

## Verificación cruzada por API

1. Abre `http://localhost:8000/api/xml/records/ID_XML`. Confirma `schema_name`, el texto de diagnóstico actualizado y la nota editada.
2. Abre `http://localhost:8000/api/xml/records/relational` y busca `ID_XML`. Los campos extraídos deben coincidir con el documento.
3. En Swagger ejecuta `GET /api/xml/records/{record_id}/nodes` con `record_id=ID_XML`, `xpath=/gh:clinicalRecord/gh:diagnosis` y `namespaces={"gh":"https://globalhealth.example/xml/clinical-record/v1"}`. Debe devolver un arreglo `nodes` con un elemento.

## Caso de error esperado

1. Pulsa **Nuevo expediente**, conserva `clinical-record-v1 · v1.0` y escribe únicamente `<clinicalRecord>`.
2. Pulsa **Validar y guardar**. Debe permanecer abierto el editor y aparecer **XML malformado** con la decisión recibida del backend/PostgreSQL. No debe crearse una fila.
3. Como segunda prueba, usa un XML bien formado pero cambia `PAT-260817` por `PACIENTE-INVALIDO`. Debe aparecer **XML no conforme al XSD** porque el XSD exige `PAT-` seguido de seis dígitos.

## Comprobación API-only del CRUD de la plantilla XSD

La SPA no tiene pantalla para administrar esquemas. Si el jurado exige ver ese CRUD, usa Swagger. **Esto crea y luego borra un XSD temporal; no uses `clinical-record-v1`.**

1. Ejecuta `POST /api/xml/schemas` con:

```json
{
  "schema_name": "demo-defense-xsd-20260817",
  "schema_version": "1.0",
  "namespace_uri": "urn:globalhealth:demo:defense",
  "xsd_document": "<?xml version=\"1.0\" encoding=\"UTF-8\"?><xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\" targetNamespace=\"urn:globalhealth:demo:defense\" xmlns=\"urn:globalhealth:demo:defense\" elementFormDefault=\"qualified\"><xs:element name=\"demo\" type=\"xs:string\"/></xs:schema>"
}
```

Debe responder **201**.

2. Ejecuta `GET /api/xml/schemas/{schema_name}` con ese nombre. Debe responder versión `1.0`.
3. Ejecuta `PUT /api/xml/schemas/{schema_name}` con el mismo namespace y XSD, pero `schema_version: "1.1"`. Debe responder **200** y versión `1.1`.
4. Ejecuta `DELETE /api/xml/schemas/{schema_name}`. Debe responder **204**. El borrado es permanente y deliberado, pero afecta solo la plantilla temporal sin expedientes asociados.

## Limpieza advertida

Selecciona `ID_XML`, pulsa **Eliminar** y confirma. Debes ver **Expediente eliminado.** El borrado es permanente y solo debe hacerse sobre el expediente `DEMO-20260817`.

## Qué hacer si no ves lo esperado

- Si el selector XSD está vacío, abre `/api/xml/schemas`; el esquema no se registró al inicializar el volumen.
- Si un XML válido es rechazado, verifica primero namespace, orden de elementos, patrón `PAT-000000`, patrón `MED-00000`, versión `1.0` y valores permitidos de `severity`.
- Si XPath devuelve cero resultados, casi siempre falta el prefijo `gh` o el JSON de namespaces no coincide exactamente con el namespace del XSD.

---

# 4. Telemetría MongoDB

## Qué se está demostrando

“Las colecciones conservan la dependencia Abuelo–Padre–Hijo `Patient → Session → Sensor Logs`; MongoDB filtra por fechas, agrega mínimo/máximo/promedio/conteo y hace `$lookup` para recuperar el nombre del paciente.”

## Pre-condición

- Backend, frontend y el proveedor MongoDB elegido saludables.
- El proveedor debe contener las semillas: Ana Solis (`SEED-P001`), Marco Vargas (`SEED-P002`), Alex Mora (`SEED-P003`), tres sesiones y cinco logs.
- En Atlas, esas mismas colecciones, validadores, índices y semillas deben existir en `MONGODB_DB`; cambiar solo `provider` no copia datos automáticamente.

## Pasos en la interfaz

1. En el menú, pulsa **Telemetría**. Señala la franja **Patient → Session → Sensor Logs**.
2. En **Pacientes**, elige **Ana Solis**, identificador `SEED-P001`, estado **Activo**.
3. En **Sesiones de Ana Solis**, selecciona `SEED-S001`. Debes ver dispositivo `ECG-CR-001`, estado `completed` y dos filas de **Frecuencia cardíaca**: `72 bpm` y `78 bpm`.
4. Selecciona `SEED-S002`. Debes ver dispositivo `OXI-CR-004`, estado `active` y dos filas de **Saturación de oxígeno**: `97 %` y `95 %`.
5. En **Resumen por sensor**, confirma para Ana:
   - frecuencia cardíaca: promedio `75`, mínimo `72`, máximo `78`, cantidad `2`;
   - saturación: promedio `96`, mínimo `95`, máximo `97`, cantidad `2`.
6. En **Desde** elige `2026-07-21` y en **Hasta** elige `2026-07-21`. Las dos pestañas de sesión siguen visibles —la API de sesiones no recibe ese filtro—, pero con `SEED-S002` seleccionada solo debes ver sus logs de oxígeno y el resumen de oxígeno de ese día.
7. Pulsa **Limpiar fechas**. Deben volver el resumen cardíaco y el de oxígeno; al alternar las dos sesiones vuelven a verse sus logs sin filtro de fecha.

## Verificación cruzada por API

1. Abre `http://localhost:8000/api/patients/SEED-P001/telemetry?sessionLimit=20&logsPerSession=100`. Debes ver el paciente, dos sesiones anidadas y dos logs dentro de cada sesión. Esta respuesta materializa la jerarquía con `$lookup`.
2. Abre `http://localhost:8000/api/sessions?patientId=SEED-P001&limit=100`. Debe devolver `SEED-S002` y `SEED-S001`.
3. Abre `http://localhost:8000/api/sensor-logs?sessionId=SEED-S001&limit=500`. Debe devolver dos logs cardíacos.
4. Abre `http://localhost:8000/api/telemetry/summary?patientId=SEED-P001&limit=50`. Debe incluir `patientName: "Ana Solis"` y los valores agregados vistos en la SPA.

## Caso de error esperado

En Swagger ejecuta `POST /api/sensor-logs` con:

```json
{
  "logId": "DEMO-ERROR-20260817",
  "sessionId": "SESION-INEXISTENTE",
  "patientId": "SEED-P001",
  "sensorType": "heart_rate",
  "value": 80,
  "unit": "bpm",
  "recordedAt": "2026-08-17T09:00:00-06:00"
}
```

Debe responder **404** y `"detail":"sessionId and patientId relationship does not exist"`. No inserta el log porque no existe la relación padre–hijo.

No uses un alta exitosa “solo para probar”: la API actual no ofrece borrado de pacientes, sesiones ni logs. Si decides insertar algo, quedará persistente y tendrás que limpiarlo por un procedimiento de base de datos fuera de esta guía.

## Qué hacer si no ves lo esperado

- Si aparecen pacientes pero no sesiones/logs, el proveedor activo tiene semillas parciales; compara las tres URLs anteriores.
- Si el resumen está vacío pero hay logs, confirma `patientId` y elimina el filtro de fechas; el frontend convierte las fechas a límites ISO del día completo.
- Si local funciona y Atlas no, comprueba `/api/mongodb/health`: lista IP, DNS/TLS, credencial rotada o falta de semillas/validadores en la base Atlas son las causas probables.

---

# 5. Fragmentación / Distribución

## Qué se está demostrando

“La horizontal guarda filas completas en nodos NORTH y SOUTH y las reconstruye con `UNION ALL`; la vertical separa columnas públicas y financieras en nodos físicos y las reconstruye con `JOIN USING (patient_id)`.”

## Pre-condición

- Los cuatro nodos de fragmentos, los dos coordinadores, backend y frontend saludables.
- Semillas esperadas: horizontal 3 NORTH + 3 SOUTH; vertical 6 claves presentes en ambos lados.

## Pasos en la interfaz

1. En el menú, pulsa **Distribución**.
2. En **Fragmentación horizontal por región**, confirma el flujo **NORTH + SOUTH → UNION ALL → patients_all**.
3. Debes ver `3` en NORTH, `3` en SOUTH y `6` en la vista global. En NORTH deben figurar Ana Torres, Luis Ramirez y Maria Gonzalez; en SOUTH, Sofia Diaz, Juan Ortega y Carlos Perez.
4. Señala la nota **Reconstrucción global: `patients_north UNION ALL patients_south`**. Cada tarjeta conserva todos los atributos de una fila y muestra su región.
5. En **Fragmentación vertical por dominio**, confirma **patients_public**, clave compartida **patient_id**, `JOIN`, **patients_financial** y resultado **patients_full**.
6. Debes ver `6 pacientes`. En una ficha, compara **Datos públicos** (teléfono, correo, dirección, emergencia) con **Datos financieros** (aseguradora, póliza, saldo, pago).
7. Señala la nota **Reconstrucción vertical: `patients_public JOIN patients_financial USING (patient_id)`**.

## Verificación cruzada por API

1. Abre `http://localhost:8000/api/fragmentation/horizontal/summary`. Debe devolver `total: 6`, `NORTH: 3`, `SOUTH: 3` y `view: "patients_all"`.
2. Abre `http://localhost:8000/api/fragmentation/horizontal?limit=500`. Cada paciente debe incluir exactamente una región.
3. Abre `http://localhost:8000/api/fragmentation/vertical/summary`. Debe devolver `reconstructedPatients: 6`, `view: "patients_full"` y separar `fieldSources.public` de `fieldSources.financial`.
4. Abre `http://localhost:8000/api/fragmentation/vertical?limit=500`. Cada fila reconstruida debe contener una sola `patientId` y campos de ambos dominios.

## Caso de error esperado

Abre `http://localhost:8000/api/fragmentation/horizontal?limit=501`. Debe responder **422**, porque la API limita la consulta a 500 filas. No modifica datos.

La regla fuerte “región distinta de NORTH/SOUTH” y el rechazo de un `patient_id` repetido entre fragmentos sí existen en la función SQL `insert_patient`, pero **no tienen endpoint ni formulario**. No prometas demostrar esas dos escrituras desde el navegador. Para probarlas se requiere la prueba de fragmentación o acceso SQL fuera del alcance browser-only.

## Qué hacer si no ves lo esperado

- Si falla toda la página, abre cada uno de los cuatro endpoints: así identificas si falló el coordinador horizontal o el vertical.
- Si horizontal no suma 6, falta una semilla, un nodo regional no responde o el volumen conserva datos de otra práctica.
- Si vertical reconstruye menos de 6, alguna clave está ausente en el fragmento público o financiero; el `INNER JOIN` excluye huérfanos por diseño.

---

# 6. Replicación

## Qué se está demostrando

“El backend mantiene conexiones físicas separadas: las escrituras usan Primary, el dashboard usa Replica; al caer Primary, la lectura continúa sin promoción automática y las escrituras se rechazan.”

## Pre-condición

- Primary y Replica saludables y en streaming antes de empezar.
- Dashboard abierto y `/dashboard` respondiendo `source: replica`, `in_recovery: true`.
- Para el tramo de caos, debe estar acordado quién detiene y recupera únicamente `postgres-primary`. Esa acción no puede hacerse desde la SPA ni Swagger.
- No se deben eliminar contenedores ni volúmenes. Detener/reiniciar el servicio es reversible; borrar volúmenes no lo es.

## Pasos en la interfaz

1. Con ambos nodos activos, abre **Vista general** y pulsa **Actualizar**. Confirma Primary y Replica `Healthy`.
2. En otra pestaña, abre `/dashboard` y enseña `source: replica` e `in_recovery: true`.
3. En Swagger ejecuta `POST /chaos/replication/write` con `probe_id=DEMO-20260817-UP`. Debe responder **201**, `status: created`. Este probe crea una fila real de prueba; es inocua para el dominio clínico, pero persiste en la tabla técnica.
4. Solicita la parada externa controlada de **solo** `postgres-primary`. No borres ni recrees nada.
5. Vuelve al Dashboard y pulsa **Actualizar**. Debes ver Primary `Offline`, Replica `Healthy`, plataforma `Degraded` y las métricas todavía visibles con **Fuente: Replica**.
6. Abre `/dashboard` otra vez. Debe seguir respondiendo **200** con `source: replica` e `in_recovery: true`.
7. En Swagger ejecuta `POST /chaos/replication/write` con `probe_id=DEMO-20260817-DOWN`. Debe responder **503** con **PostgreSQL Primary is unavailable**; esa fila no se crea.
8. Solicita la recuperación externa de `postgres-primary` y espera a que vuelva saludable y el streaming se restablezca.
9. Pulsa **Actualizar**. Deben regresar Primary y Replica a `Healthy`.
10. Ejecuta `POST /chaos/replication/write` con `probe_id=DEMO-20260817-RECOVERED`. Debe responder **201**.

## Verificación cruzada por API

- Normal: `/health/databases` devuelve **200**, Primary `in_recovery: false` y Replica `in_recovery: true`.
- Durante caída: `/dashboard` conserva **200**; `/health/databases` devuelve **503** con Primary `unhealthy` y Replica `healthy`.
- Recuperado: `/health/databases` vuelve a **200** con ambos `healthy`.

La API no expone una lectura de `chaos_replication_probe`, por lo que el navegador comprueba aceptación/rechazo HTTP y la continuidad del dashboard, pero no puede confirmar que el probe llegó físicamente a Replica. Esa comprobación puntual requiere el script/SQL de replicación fuera del recorrido browser-only.

## Caso de error esperado

El caso de negocio esperado es el paso 7: escritura **503** mientras Primary está detenido. La Replica no debe promoverse ni aceptar esa escritura. Si la escritura devuelve 201 durante la supuesta caída, se detuvo el servicio incorrecto o el Primary no estaba realmente fuera de línea.

## Qué hacer si no ves lo esperado

- Si al detener Primary también cae `/dashboard`, la Replica o el backend se detuvieron, o el pool de lectura no apunta a `postgres-replica`.
- Si Replica muestra `Degraded`, puede haberse perdido el receptor WAL; recupera Primary y espera el restablecimiento antes de continuar.
- Si Primary vuelve pero el estado no cambia, espera unos segundos y pulsa **Actualizar**; si persiste, la recuperación/streaming no concluyó. No improvises una promoción.

---

# Secuencia recomendada para una defensa de 15 minutos

| Tiempo | Sección | Historia que cuentas |
| --- | --- | --- |
| 0:00–1:15 | Dashboard | “Una sola SPA integra tres modelos y una infraestructura distribuida; el dashboard ya lee de Replica.” |
| 1:15–3:45 | MOR | Abre Ana para mostrar tipos/arreglos; registra el médico demo, agrega especialidad/teléfono y enseña el mismo JSON. Deja la limpieza para después. |
| 3:45–6:30 | XML/XSD | Inserta el XML válido, abre XMLTABLE, consulta y reemplaza diagnóstico; muestra un XML inválido rechazado. No hagas el CRUD de plantilla salvo que lo pregunten. |
| 6:30–8:45 | MongoDB/Atlas | Sigue Ana Solis → sesiones → logs → resumen; abre la jerarquía anidada y salud `provider: atlas` si realmente estás en Atlas. |
| 8:45–10:45 | Fragmentación | Compara 3 NORTH + 3 SOUTH = 6 y luego columnas públicas/financieras unidas por la PK. |
| 10:45–13:45 | Replicación/caos | Observa roles, detén Primary externamente, conserva dashboard, rechaza escritura, recupera y confirma salud. |
| 13:45–15:00 | Cierre | Explica CAP/consistencia eventual y el costo mensual estimado: bajo los supuestos documentados, autoadministrado USD 115.60 frente a Atlas Flex USD 33.00. Aclara que precio/tier real deben confirmarse con la evidencia actual, no solo con la estimación. |

Ensaya también una versión de 10 minutos omitiendo altas exitosas de MOR, CRUD de plantilla XSD y limpieza en vivo. La limpieza de los datos demo puede hacerse inmediatamente después de la defensa.

# Checklist “iría mal en frío”: 10 minutos antes

## Infraestructura

- Los 11 servicios del perfil local figuran activos y saludables. Si usas Atlas, confirma de antemano cuál es el conjunto intencional de servicios; no confundas el MongoDB local encendido con el proveedor realmente consumido.
- `http://localhost:3000/`, `http://localhost:3000/clinical-records` y `http://localhost:8000/docs` abren directamente. La segunda URL confirma que el fallback de la SPA soporta refresco.
- `/health/databases` devuelve Primary `false`, Replica `true`; `/dashboard` dice `source: replica`.
- Los puertos 3000 y 8000 están libres y corresponden a esta copia del proyecto.

## Datos

- Personal muestra Ana Solano y Luis Vargas.
- `/api/xml/schemas` contiene `clinical-record-v1`; no importa que la lista de expedientes esté vacía.
- Telemetría muestra Ana Solis, Marco Vargas y Alex Mora; Ana tiene `SEED-S001` y `SEED-S002`.
- Distribución muestra horizontal 3 + 3 = 6 y vertical 6.
- No quedan `DEMO-20260817` ni `demo-defense-xsd-20260817` de ensayos previos que puedan provocar conflictos.

## Atlas y seguridad

- `/api/mongodb/health` devuelve `healthy`, `provider: atlas` y la base esperada si vas a demostrar nube. Si dice `local`, no presentes esa ejecución como Atlas.
- La IP de salida de la sede está autorizada de forma restrictiva en Atlas; la credencial rotada sigue vigente; TLS/DNS funcionan.
- Las colecciones, validadores, índices y semillas existen en la base Atlas seleccionada.
- Ninguna pestaña, historial visible, archivo o proyección muestra la URI o contraseña.
- Ten abierta por separado la tabla de costo/beneficio de `docs/final-documentation.md`; esa información no está en la SPA.

## Frontend y ensayo

- El frontend visible corresponde al build actual: menú con **Vista general**, **Personal**, **Expedientes**, **Telemetría** y **Distribución**.
- Prueba **Actualizar** y navega una vez por cada módulo; no dependas de caché de una pestaña vieja.
- Deja preparadas pestañas para `/docs`, `/dashboard`, `/health/databases`, salud MongoDB y los cuatro endpoints de fragmentación.
- Ten copiado el XML válido en un lugar que no exponga secretos y practica pegarlo sin alterar comillas o namespace.
- Acuerda la señal para detener y recuperar exclusivamente Primary. Confirma antes que nadie ejecutará una eliminación de volúmenes.
- Conserva un plan de salida: si el caos no recupera a tiempo, muestra los estados ya observados, declara la limitación y pasa al cierre; no improvises cambios de infraestructura frente al jurado.

# Limpieza después del ensayo o defensa

- Elimina desde **Personal** únicamente el médico cuya licencia sea `DEMO-20260817`.
- Elimina desde **Expedientes** únicamente el documento cuya nota contenga `DEMO-20260817`.
- Si hiciste el CRUD XSD, confirma que `demo-defense-xsd-20260817` ya no aparece en `/api/xml/schemas`.
- Los probes de replicación quedan en una tabla técnica y no afectan datos clínicos. No existe borrado HTTP; evita inventar un procedimiento destructivo durante la defensa.
- No borres volúmenes para “limpiar” estos datos. Eso eliminaría también semillas y datos persistentes de todo el entorno.

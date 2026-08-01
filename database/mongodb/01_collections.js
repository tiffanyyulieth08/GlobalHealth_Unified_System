const databaseName = process.env.MONGODB_DB || "globalhealth";
const telemetryDb = db.getSiblingDB(databaseName);

const validators = {
  patients: {
    $jsonSchema: {
      bsonType: "object",
      required: ["patientId", "firstName", "lastName", "dateOfBirth", "sex", "active"],
      properties: {
        patientId: { bsonType: "string", minLength: 1 },
        firstName: { bsonType: "string", minLength: 1 },
        lastName: { bsonType: "string", minLength: 1 },
        dateOfBirth: { bsonType: "date" },
        sex: { enum: ["female", "male", "other", "unknown"] },
        active: { bsonType: "bool" },
        createdAt: { bsonType: "date" }
      }
    }
  },
  sessions: {
    $jsonSchema: {
      bsonType: "object",
      required: ["sessionId", "patientId", "deviceId", "startedAt", "status"],
      properties: {
        sessionId: { bsonType: "string", minLength: 1 },
        patientId: { bsonType: "string", minLength: 1 },
        deviceId: { bsonType: "string", minLength: 1 },
        startedAt: { bsonType: "date" },
        endedAt: { bsonType: ["date", "null"] },
        status: { enum: ["active", "completed", "cancelled"] },
        createdAt: { bsonType: "date" }
      }
    }
  },
  sensor_logs: {
    $jsonSchema: {
      bsonType: "object",
      required: [
        "logId",
        "sessionId",
        "patientId",
        "sensorType",
        "value",
        "unit",
        "recordedAt"
      ],
      properties: {
        logId: { bsonType: "string", minLength: 1 },
        sessionId: { bsonType: "string", minLength: 1 },
        patientId: { bsonType: "string", minLength: 1 },
        sensorType: {
          enum: ["heart_rate", "oxygen_saturation", "temperature", "blood_pressure"]
        },
        value: { bsonType: ["double", "int", "long", "decimal"] },
        unit: { bsonType: "string", minLength: 1 },
        recordedAt: { bsonType: "date" }
      }
    }
  }
};

for (const [collectionName, validator] of Object.entries(validators)) {
  if (!telemetryDb.getCollectionNames().includes(collectionName)) {
    telemetryDb.createCollection(collectionName, { validator });
  } else {
    telemetryDb.runCommand({ collMod: collectionName, validator });
  }
}

telemetryDb.patients.createIndex({ patientId: 1 }, { unique: true, name: "uq_patient_id" });
telemetryDb.patients.createIndex({ active: 1, lastName: 1 }, { name: "ix_patient_active_name" });
telemetryDb.sessions.createIndex({ sessionId: 1 }, { unique: true, name: "uq_session_id" });
telemetryDb.sessions.createIndex(
  { patientId: 1, startedAt: -1 },
  { name: "ix_session_patient_started" }
);
telemetryDb.sensor_logs.createIndex({ logId: 1 }, { unique: true, name: "uq_log_id" });
telemetryDb.sensor_logs.createIndex(
  { sessionId: 1, recordedAt: -1 },
  { name: "ix_log_session_recorded" }
);
telemetryDb.sensor_logs.createIndex(
  { patientId: 1, sensorType: 1, recordedAt: -1 },
  { name: "ix_log_patient_sensor_recorded" }
);

print(`Collections and indexes ready in ${databaseName}.`);

const databaseName = process.env.MONGODB_DB || "globalhealth";
const telemetryDb = db.getSiblingDB(databaseName);

telemetryDb.sensor_logs.deleteMany({ logId: /^SEED-/ });
telemetryDb.sessions.deleteMany({ sessionId: /^SEED-/ });
telemetryDb.patients.deleteMany({ patientId: /^SEED-/ });

telemetryDb.patients.insertMany([
  {
    patientId: "SEED-P001",
    firstName: "Ana",
    lastName: "Solis",
    dateOfBirth: ISODate("1988-04-12T00:00:00Z"),
    sex: "female",
    active: true,
    createdAt: ISODate("2026-07-01T14:00:00Z")
  },
  {
    patientId: "SEED-P002",
    firstName: "Marco",
    lastName: "Vargas",
    dateOfBirth: ISODate("1975-09-23T00:00:00Z"),
    sex: "male",
    active: true,
    createdAt: ISODate("2026-07-02T14:00:00Z")
  },
  {
    patientId: "SEED-P003",
    firstName: "Alex",
    lastName: "Mora",
    dateOfBirth: ISODate("1995-01-05T00:00:00Z"),
    sex: "other",
    active: false,
    createdAt: ISODate("2026-07-03T14:00:00Z")
  }
]);

telemetryDb.sessions.insertMany([
  {
    sessionId: "SEED-S001",
    patientId: "SEED-P001",
    deviceId: "ECG-CR-001",
    startedAt: ISODate("2026-07-20T08:00:00Z"),
    endedAt: ISODate("2026-07-20T08:30:00Z"),
    status: "completed",
    createdAt: ISODate("2026-07-20T08:00:00Z")
  },
  {
    sessionId: "SEED-S002",
    patientId: "SEED-P001",
    deviceId: "OXI-CR-004",
    startedAt: ISODate("2026-07-21T09:00:00Z"),
    endedAt: null,
    status: "active",
    createdAt: ISODate("2026-07-21T09:00:00Z")
  },
  {
    sessionId: "SEED-S003",
    patientId: "SEED-P002",
    deviceId: "TEMP-CR-002",
    startedAt: ISODate("2026-07-22T10:00:00Z"),
    endedAt: ISODate("2026-07-22T10:15:00Z"),
    status: "completed",
    createdAt: ISODate("2026-07-22T10:00:00Z")
  }
]);

telemetryDb.sensor_logs.insertMany([
  {
    logId: "SEED-L001",
    sessionId: "SEED-S001",
    patientId: "SEED-P001",
    sensorType: "heart_rate",
    value: 72,
    unit: "bpm",
    recordedAt: ISODate("2026-07-20T08:01:00Z")
  },
  {
    logId: "SEED-L002",
    sessionId: "SEED-S001",
    patientId: "SEED-P001",
    sensorType: "heart_rate",
    value: 78,
    unit: "bpm",
    recordedAt: ISODate("2026-07-20T08:02:00Z")
  },
  {
    logId: "SEED-L003",
    sessionId: "SEED-S002",
    patientId: "SEED-P001",
    sensorType: "oxygen_saturation",
    value: 97,
    unit: "%",
    recordedAt: ISODate("2026-07-21T09:01:00Z")
  },
  {
    logId: "SEED-L004",
    sessionId: "SEED-S002",
    patientId: "SEED-P001",
    sensorType: "oxygen_saturation",
    value: 95,
    unit: "%",
    recordedAt: ISODate("2026-07-21T09:02:00Z")
  },
  {
    logId: "SEED-L005",
    sessionId: "SEED-S003",
    patientId: "SEED-P002",
    sensorType: "temperature",
    value: 37.2,
    unit: "C",
    recordedAt: ISODate("2026-07-22T10:01:00Z")
  }
]);

print("Seed data inserted.");

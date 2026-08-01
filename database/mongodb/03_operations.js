const databaseName = process.env.MONGODB_DB || "globalhealth";
const telemetryDb = db.getSiblingDB(databaseName);

telemetryDb.sensor_logs.deleteMany({ logId: /^DEMO-/ });
telemetryDb.sessions.deleteMany({ sessionId: /^DEMO-/ });
telemetryDb.patients.deleteMany({ patientId: /^DEMO-/ });

telemetryDb.patients.insertOne({
  patientId: "DEMO-P001",
  firstName: "Lucia",
  lastName: "Castro",
  dateOfBirth: ISODate("1992-06-18T00:00:00Z"),
  sex: "female",
  active: true,
  createdAt: new Date()
});

telemetryDb.sessions.insertOne({
  sessionId: "DEMO-S001",
  patientId: "DEMO-P001",
  deviceId: "ECG-DEMO-001",
  startedAt: ISODate("2026-07-30T15:00:00Z"),
  endedAt: null,
  status: "active",
  createdAt: new Date()
});

telemetryDb.sensor_logs.insertMany([
  {
    logId: "DEMO-L001",
    sessionId: "DEMO-S001",
    patientId: "DEMO-P001",
    sensorType: "heart_rate",
    value: 80,
    unit: "bpm",
    recordedAt: ISODate("2026-07-30T15:01:00Z")
  },
  {
    logId: "DEMO-L002",
    sessionId: "DEMO-S001",
    patientId: "DEMO-P001",
    sensorType: "heart_rate",
    value: 84,
    unit: "bpm",
    recordedAt: ISODate("2026-07-30T15:02:00Z")
  },
  {
    logId: "DEMO-L003",
    sessionId: "DEMO-S001",
    patientId: "DEMO-P001",
    sensorType: "heart_rate",
    value: 76,
    unit: "bpm",
    recordedAt: ISODate("2026-07-30T15:03:00Z")
  }
]);

telemetryDb.patients.updateOne(
  { patientId: "DEMO-P001" },
  { $set: { active: true, updatedAt: new Date() } }
);
telemetryDb.sensor_logs.updateMany(
  { sessionId: "DEMO-S001", sensorType: "heart_rate" },
  { $set: { reviewed: false } }
);

print("Filtered active patients:");
printjson(
  telemetryDb.patients
    .find({ active: true }, { _id: 0 })
    .sort({ lastName: 1, firstName: 1 })
    .limit(5)
    .toArray()
);

print("Latest high heart-rate readings:");
printjson(
  telemetryDb.sensor_logs
    .find(
      { sensorType: "heart_rate", value: { $gte: 75 } },
      { _id: 0, logId: 1, sessionId: 1, value: 1, unit: 1, recordedAt: 1 }
    )
    .sort({ recordedAt: -1 })
    .limit(3)
    .toArray()
);

print("CRUD operations completed.");

const databaseName = process.env.MONGODB_DB || "globalhealth";
const telemetryDb = db.getSiblingDB(databaseName);

function assertCondition(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function expectRejected(action, message) {
  try {
    action();
  } catch (error) {
    return;
  }
  throw new Error(message);
}

for (const collectionName of ["patients", "sessions", "sensor_logs"]) {
  assertCondition(
    telemetryDb.getCollectionNames().includes(collectionName),
    `Missing collection: ${collectionName}`
  );
}

assertCondition(
  telemetryDb.patients.countDocuments({ patientId: /^SEED-/ }) === 3,
  "Expected three seed patients"
);
assertCondition(
  telemetryDb.sessions.countDocuments({ patientId: "SEED-P001" }) === 2,
  "Expected two sessions related to SEED-P001"
);
assertCondition(
  telemetryDb.sensor_logs.countDocuments({ sessionId: "SEED-S001" }) === 2,
  "Expected two logs related to SEED-S001"
);

const patientIndexes = telemetryDb.patients.getIndexes();
const sessionIndexes = telemetryDb.sessions.getIndexes();
const logIndexes = telemetryDb.sensor_logs.getIndexes();
assertCondition(patientIndexes.some((index) => index.name === "uq_patient_id"), "Missing patient index");
assertCondition(
  sessionIndexes.some((index) => index.name === "ix_session_patient_started"),
  "Missing session relationship index"
);
assertCondition(
  logIndexes.some((index) => index.name === "ix_log_session_recorded"),
  "Missing log relationship index"
);

print("Validators reject invalid documents:");
expectRejected(
  () =>
    telemetryDb.patients.insertOne({
      patientId: "INVALID-P001",
      firstName: "Inv",
      dateOfBirth: ISODate("2000-01-01T00:00:00Z"),
      sex: "female",
      active: true
    }),
  "Validator accepted a patient without lastName"
);
expectRejected(
  () =>
    telemetryDb.patients.insertOne({
      patientId: "INVALID-P002",
      firstName: "Inv",
      lastName: "Alid",
      dateOfBirth: ISODate("2000-01-01T00:00:00Z"),
      sex: "martian",
      active: true
    }),
  "Validator accepted a patient with an invalid sex value"
);
print("OK: validators reject invalid documents");

print("Unique indexes reject duplicate keys:");
expectRejected(
  () =>
    telemetryDb.patients.insertOne({
      patientId: "SEED-P001",
      firstName: "Dup",
      lastName: "Licado",
      dateOfBirth: ISODate("2000-01-01T00:00:00Z"),
      sex: "female",
      active: true
    }),
  "Unique index accepted a duplicate patientId"
);
expectRejected(
  () =>
    telemetryDb.sessions.insertOne({
      sessionId: "SEED-S001",
      patientId: "SEED-P002",
      deviceId: "ECG-CR-999",
      startedAt: ISODate("2026-07-20T08:00:00Z"),
      status: "completed"
    }),
  "Unique index accepted a duplicate sessionId"
);
print("OK: unique indexes reject duplicate keys");

print("Updates persist changes:");
const updateResult = telemetryDb.patients.updateOne(
  { patientId: "SEED-P003" },
  { $set: { active: true } }
);
assertCondition(updateResult.modifiedCount === 1, "Update did not modify SEED-P003");
assertCondition(
  telemetryDb.patients.findOne({ patientId: "SEED-P003" }).active === true,
  "Update change was not persisted"
);
print("OK: update persisted the change");

print("Deletions remove documents:");
telemetryDb.sensor_logs.insertOne({
  logId: "TMP-L999",
  sessionId: "SEED-S001",
  patientId: "SEED-P001",
  sensorType: "heart_rate",
  value: 1,
  unit: "bpm",
  recordedAt: ISODate("2026-07-20T08:03:00Z")
});
const deleteResult = telemetryDb.sensor_logs.deleteOne({ logId: "TMP-L999" });
assertCondition(deleteResult.deletedCount === 1, "Delete did not remove TMP-L999");
assertCondition(
  telemetryDb.sensor_logs.countDocuments({ logId: "TMP-L999" }) === 0,
  "Deleted log still present"
);
print("OK: delete removed the document");

print("Comparison filters with limit and sort:");
const highRate = telemetryDb.sensor_logs
  .find(
    { patientId: "SEED-P001", sensorType: "heart_rate", value: { $gte: 70 } },
    { _id: 0, logId: 1, value: 1 }
  )
  .sort({ value: -1 })
  .limit(2)
  .toArray();
assertCondition(highRate.length === 2, "limit did not cap results");
assertCondition(highRate[0].value >= highRate[1].value, "sort descending was not applied");
assertCondition(
  highRate.every((log) => log.value >= 70),
  "comparison filter (>=) was not applied"
);
assertCondition(
  highRate.map((log) => log.logId).join(",") === "SEED-L002,SEED-L001",
  "sort/limit did not return the expected order"
);
print("OK: comparison filter, limit and sort verified");

print("Aggregation (group, sum, min, max, avg):");
const summary = telemetryDb.sensor_logs
  .aggregate([
    { $match: { patientId: "SEED-P001" } },
    {
      $group: {
        _id: "$sensorType",
        samples: { $sum: 1 },
        minimum: { $min: "$value" },
        maximum: { $max: "$value" },
        average: { $avg: "$value" }
      }
    }
  ])
  .toArray();
const heartRateGroup = summary.find((entry) => entry._id === "heart_rate");
const oxygenGroup = summary.find((entry) => entry._id === "oxygen_saturation");
assertCondition(heartRateGroup.samples === 2, "Aggregation samples for heart_rate wrong");
assertCondition(heartRateGroup.minimum === 72, "Aggregation minimum for heart_rate wrong");
assertCondition(heartRateGroup.maximum === 78, "Aggregation maximum for heart_rate wrong");
assertCondition(heartRateGroup.average === 75, "Aggregation average for heart_rate wrong");
assertCondition(oxygenGroup.samples === 2, "Aggregation samples for oxygen wrong");
assertCondition(oxygenGroup.average === 96, "Aggregation average for oxygen wrong");
print("OK: aggregation verified");

const joined = telemetryDb.patients
  .aggregate([
    { $match: { patientId: "SEED-P001" } },
    {
      $lookup: {
        from: "sessions",
        localField: "patientId",
        foreignField: "patientId",
        as: "sessions"
      }
    },
    { $unwind: "$sessions" },
    {
      $lookup: {
        from: "sensor_logs",
        localField: "sessions.sessionId",
        foreignField: "sessionId",
        as: "sessions.logs"
      }
    },
    { $group: { _id: "$patientId", sessions: { $push: "$sessions" } } }
  ])
  .toArray();

assertCondition(joined.length === 1, "Lookup did not return the patient");
assertCondition(joined[0].sessions.length === 2, "Lookup did not return both sessions");
assertCondition(
  joined[0].sessions.reduce((total, session) => total + session.logs.length, 0) === 4,
  "Lookup did not return all patient logs"
);

print("All MongoDB tests passed.");

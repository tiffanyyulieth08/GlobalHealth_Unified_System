const databaseName = process.env.MONGODB_DB || "globalhealth";
const telemetryDb = db.getSiblingDB(databaseName);

function assertCondition(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
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

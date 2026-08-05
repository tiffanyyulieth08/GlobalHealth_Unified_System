const databaseName = process.env.MONGODB_DB;
const nodeAssert = require("node:assert/strict");

if (!/^gh_atlas_[A-Za-z0-9_-]+$/.test(databaseName)) {
  throw new Error("Unsafe Atlas validation database name");
}

const validationDb = db.getSiblingDB(databaseName);

validationDb.patients.insertOne({
  patientId: "ATLAS-P001",
  firstName: "Atlas",
  lastName: "Validation",
  dateOfBirth: ISODate("1990-01-01T00:00:00Z"),
  sex: "unknown",
  active: true,
  createdAt: new Date()
});
validationDb.sessions.insertOne({
  sessionId: "ATLAS-S001",
  patientId: "ATLAS-P001",
  deviceId: "ATLAS-DEVICE-01",
  startedAt: ISODate("2026-08-04T12:00:00Z"),
  status: "active",
  createdAt: new Date()
});
validationDb.sensor_logs.insertMany([
  {
    logId: "ATLAS-L001",
    sessionId: "ATLAS-S001",
    patientId: "ATLAS-P001",
    sensorType: "heart_rate",
    value: 70,
    unit: "bpm",
    recordedAt: ISODate("2026-08-04T12:01:00Z")
  },
  {
    logId: "ATLAS-L002",
    sessionId: "ATLAS-S001",
    patientId: "ATLAS-P001",
    sensorType: "heart_rate",
    value: 74,
    unit: "bpm",
    recordedAt: ISODate("2026-08-04T12:02:00Z")
  }
]);

const updateResult = validationDb.sessions.updateOne(
  { sessionId: "ATLAS-S001" },
  { $set: { status: "completed", endedAt: ISODate("2026-08-04T12:03:00Z") } }
);
nodeAssert.strictEqual(updateResult.modifiedCount, 1, "update failed");

const queriedLog = validationDb.sensor_logs.findOne({ logId: "ATLAS-L001" });
nodeAssert.strictEqual(queriedLog.value, 70, "query failed");

const summary = validationDb.sensor_logs.aggregate([
  { $match: { patientId: "ATLAS-P001" } },
  {
    $group: {
      _id: "$sensorType",
      sampleCount: { $sum: 1 },
      average: { $avg: "$value" }
    }
  }
]).toArray();
nodeAssert.strictEqual(summary.length, 1, "aggregation returned an unexpected result");
nodeAssert.strictEqual(summary[0].sampleCount, 2, "aggregation count failed");
nodeAssert.strictEqual(summary[0].average, 72, "aggregation average failed");

const lookup = validationDb.patients.aggregate([
  { $match: { patientId: "ATLAS-P001" } },
  {
    $lookup: {
      from: "sessions",
      localField: "patientId",
      foreignField: "patientId",
      as: "sessions"
    }
  }
]).toArray();
nodeAssert.strictEqual(lookup.length, 1, "lookup patient failed");
nodeAssert.strictEqual(lookup[0].sessions.length, 1, "lookup session failed");

print("Atlas CRUD, aggregation, and lookup validation passed.");

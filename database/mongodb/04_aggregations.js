const databaseName = process.env.MONGODB_DB || "globalhealth";
const telemetryDb = db.getSiblingDB(databaseName);

print("Telemetry summary by patient and sensor:");
printjson(
  telemetryDb.sensor_logs
    .aggregate([
      {
        $group: {
          _id: { patientId: "$patientId", sensorType: "$sensorType" },
          samples: { $sum: 1 },
          minimum: { $min: "$value" },
          maximum: { $max: "$value" },
          average: { $avg: "$value" },
          lastReadingAt: { $max: "$recordedAt" }
        }
      },
      { $sort: { "_id.patientId": 1, "_id.sensorType": 1 } },
      {
        $project: {
          _id: 0,
          patientId: "$_id.patientId",
          sensorType: "$_id.sensorType",
          samples: 1,
          minimum: 1,
          maximum: 1,
          average: { $round: ["$average", 2] },
          lastReadingAt: 1
        }
      }
    ])
    .toArray()
);

const patientSessionLogsPipeline = [
  { $match: { patientId: "SEED-P001" } },
  {
    $lookup: {
      from: "sessions",
      let: { patientId: "$patientId" },
      pipeline: [
        { $match: { $expr: { $eq: ["$patientId", "$$patientId"] } } },
        { $sort: { startedAt: -1 } },
        {
          $lookup: {
            from: "sensor_logs",
            localField: "sessionId",
            foreignField: "sessionId",
            pipeline: [
              { $sort: { recordedAt: -1 } },
              { $project: { _id: 0 } }
            ],
            as: "logs"
          }
        },
        { $project: { _id: 0 } }
      ],
      as: "sessions"
    }
  },
  { $project: { _id: 0 } }
];

print("Patient -> sessions -> sensor logs:");
printjson(telemetryDb.patients.aggregate(patientSessionLogsPipeline).toArray());

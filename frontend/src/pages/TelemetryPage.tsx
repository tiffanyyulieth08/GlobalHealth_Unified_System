import { useEffect, useMemo, useState } from "react";
import {
  Activity,
  CalendarRange,
  ChevronRight,
  HeartPulse,
  Radio,
  UserRound,
  Waves,
} from "lucide-react";
import { PageHeader } from "../components/ui/PageHeader";
import { SectionCard } from "../components/ui/SectionCard";
import { Badge } from "../components/ui/Badge";
import { EmptyState, ErrorState, LoadingState } from "../components/ui/States";
import { api } from "../lib/api";

type Patient = {
  patientId: string;
  firstName: string;
  lastName: string;
  active: boolean;
};

type Session = {
  sessionId: string;
  patientId: string;
  deviceId: string;
  startedAt: string;
  endedAt: string | null;
  status: "active" | "completed" | "cancelled";
};

type SensorLog = {
  logId: string;
  sessionId: string;
  patientId: string;
  sensorType: string;
  value: number;
  unit: string;
  recordedAt: string;
};

type SummaryItem = {
  patientId: string;
  patientName: string | null;
  sensorType: string;
  unit: string;
  sampleCount: number;
  minimum: number;
  maximum: number;
  average: number;
};

type SummaryResponse = { results: SummaryItem[] };

const sensorNames: Record<string, string> = {
  blood_pressure: "Presión arterial",
  heart_rate: "Frecuencia cardíaca",
  oxygen_saturation: "Saturación de oxígeno",
  temperature: "Temperatura",
};

const dateTime = new Intl.DateTimeFormat("es-CR", {
  dateStyle: "medium",
  timeStyle: "short",
});

function formatDate(value: string | null) {
  return value ? dateTime.format(new Date(value)) : "En curso";
}

function toBoundary(value: string, endOfDay = false) {
  if (!value) return undefined;
  return new Date(`${value}T${endOfDay ? "23:59:59.999" : "00:00:00"}`).toISOString();
}

function queryString(values: Record<string, string | undefined>) {
  const query = new URLSearchParams();
  Object.entries(values).forEach(([key, value]) => value && query.set(key, value));
  return query.toString();
}

export function TelemetryPage() {
  const [patients, setPatients] = useState<Patient[]>([]);
  const [patientId, setPatientId] = useState("");
  const [sessions, setSessions] = useState<Session[]>([]);
  const [sessionId, setSessionId] = useState("");
  const [logs, setLogs] = useState<SensorLog[]>([]);
  const [summary, setSummary] = useState<SummaryItem[]>([]);
  const [dateFrom, setDateFrom] = useState("");
  const [dateTo, setDateTo] = useState("");
  const [loadingPatients, setLoadingPatients] = useState(true);
  const [loadingDetail, setLoadingDetail] = useState(false);
  const [error, setError] = useState<Error | null>(null);
  const [reload, setReload] = useState(0);

  useEffect(() => {
    const controller = new AbortController();
    setLoadingPatients(true);
    setError(null);
    api.get<Patient[]>("/api/patients?limit=100", controller.signal)
      .then((data) => {
        setPatients(data);
        setPatientId((current) => current || data[0]?.patientId || "");
      })
      .catch((reason: unknown) => {
        if (!(reason instanceof DOMException && reason.name === "AbortError")) {
          setError(reason instanceof Error ? reason : new Error("Error inesperado"));
        }
      })
      .finally(() => setLoadingPatients(false));
    return () => controller.abort();
  }, [reload]);

  useEffect(() => {
    if (!patientId) {
      setSessions([]);
      setSessionId("");
      setSummary([]);
      return;
    }
    const controller = new AbortController();
    setLoadingDetail(true);
    setError(null);
    const summaryQuery = queryString({
      patientId,
      recordedFrom: toBoundary(dateFrom),
      recordedTo: toBoundary(dateTo, true),
    });
    Promise.all([
      api.get<Session[]>(`/api/sessions?patientId=${encodeURIComponent(patientId)}&limit=100`, controller.signal),
      api.get<SummaryResponse>(`/api/telemetry/summary?${summaryQuery}`, controller.signal),
    ])
      .then(([sessionData, summaryData]) => {
        setSessions(sessionData);
        setSummary(summaryData.results);
        setSessionId((current) => sessionData.some((item) => item.sessionId === current)
          ? current
          : sessionData[0]?.sessionId || "");
      })
      .catch((reason: unknown) => {
        if (!(reason instanceof DOMException && reason.name === "AbortError")) {
          setError(reason instanceof Error ? reason : new Error("Error inesperado"));
        }
      })
      .finally(() => setLoadingDetail(false));
    return () => controller.abort();
  }, [patientId, dateFrom, dateTo, reload]);

  useEffect(() => {
    if (!sessionId) {
      setLogs([]);
      return;
    }
    const controller = new AbortController();
    setLoadingDetail(true);
    const query = queryString({
      sessionId,
      recordedFrom: toBoundary(dateFrom),
      recordedTo: toBoundary(dateTo, true),
    });
    api.get<SensorLog[]>(`/api/sensor-logs?${query}&limit=500`, controller.signal)
      .then(setLogs)
      .catch((reason: unknown) => {
        if (!(reason instanceof DOMException && reason.name === "AbortError")) {
          setError(reason instanceof Error ? reason : new Error("Error inesperado"));
        }
      })
      .finally(() => setLoadingDetail(false));
    return () => controller.abort();
  }, [sessionId, dateFrom, dateTo, reload]);

  const selectedPatient = useMemo(
    () => patients.find((patient) => patient.patientId === patientId),
    [patientId, patients],
  );

  return (
    <div className="page-stack telemetry-page">
      <PageHeader
        eyebrow="MONITOREO REMOTO · MONGODB"
        title="Telemetría médica"
        description="Explora mediciones biomédicas respetando la jerarquía documental de pacientes, sesiones y registros de sensores."
      />

      <div className="hierarchy-strip" aria-label="Jerarquía de telemetría">
        <span><UserRound size={17} /> Patient</span><ChevronRight size={16} />
        <span><Radio size={17} /> Session</span><ChevronRight size={16} />
        <span><Waves size={17} /> Sensor Logs</span>
      </div>

      {error ? <ErrorState message={error.message} onRetry={() => setReload((value) => value + 1)} /> : null}

      <div className="telemetry-layout">
        <SectionCard title="Pacientes" description="Colección patients">
          {loadingPatients ? <LoadingState label="Cargando pacientes" /> : patients.length ? (
            <div className="patient-list" role="listbox" aria-label="Seleccionar paciente">
              {patients.map((patient) => (
                <button
                  aria-selected={patient.patientId === patientId}
                  className={`patient-option${patient.patientId === patientId ? " is-selected" : ""}`}
                  key={patient.patientId}
                  onClick={() => setPatientId(patient.patientId)}
                  role="option"
                  type="button"
                >
                  <span className="patient-option__avatar">{patient.firstName[0]}{patient.lastName[0]}</span>
                  <span><strong>{patient.firstName} {patient.lastName}</strong><small>{patient.patientId}</small></span>
                  <Badge tone={patient.active ? "success" : "neutral"}>{patient.active ? "Activo" : "Inactivo"}</Badge>
                </button>
              ))}
            </div>
          ) : <EmptyState title="Sin pacientes" description="La API no devolvió pacientes registrados." />}
        </SectionCard>

        <div className="telemetry-main">
          <SectionCard
            title={selectedPatient ? `Sesiones de ${selectedPatient.firstName} ${selectedPatient.lastName}` : "Sesiones"}
            description="Colección sessions vinculada por patientId"
            action={<Badge tone="info">MongoDB</Badge>}
          >
            <div className="date-filter">
              <CalendarRange aria-hidden="true" size={18} />
              <label>Desde<input max={dateTo || undefined} onChange={(event) => setDateFrom(event.target.value)} type="date" value={dateFrom} /></label>
              <label>Hasta<input min={dateFrom || undefined} onChange={(event) => setDateTo(event.target.value)} type="date" value={dateTo} /></label>
              {(dateFrom || dateTo) && <button onClick={() => { setDateFrom(""); setDateTo(""); }} type="button">Limpiar fechas</button>}
            </div>
            {loadingDetail && !sessions.length ? <LoadingState label="Cargando sesiones" /> : sessions.length ? (
              <div className="session-tabs" role="listbox" aria-label="Seleccionar sesión">
                {sessions.map((session) => (
                  <button
                    aria-selected={session.sessionId === sessionId}
                    className={`session-option${session.sessionId === sessionId ? " is-selected" : ""}`}
                    key={session.sessionId}
                    onClick={() => setSessionId(session.sessionId)}
                    role="option"
                    type="button"
                  >
                    <span><Radio size={16} /><strong>{session.sessionId}</strong></span>
                    <small>{session.deviceId}</small>
                    <small>{formatDate(session.startedAt)}</small>
                    <Badge tone={session.status === "active" ? "success" : "neutral"}>{session.status}</Badge>
                  </button>
                ))}
              </div>
            ) : <EmptyState title="Sin sesiones" description="Este paciente no tiene sesiones de telemetría registradas." />}
          </SectionCard>

          <SectionCard title="Sensor Logs" description="Colección sensor_logs vinculada por sessionId">
            {loadingDetail && !logs.length ? <LoadingState label="Cargando registros de sensores" /> : logs.length ? (
              <div className="data-table-wrap">
                <table className="data-table">
                  <thead><tr><th>Sensor</th><th>Valor</th><th>Unidad</th><th>Fecha</th></tr></thead>
                  <tbody>{logs.map((log) => (
                    <tr key={log.logId}>
                      <td><span className="sensor-name"><HeartPulse size={15} />{sensorNames[log.sensorType] || log.sensorType}</span></td>
                      <td className="numeric-value">{log.value}</td>
                      <td>{log.unit}</td>
                      <td>{formatDate(log.recordedAt)}</td>
                    </tr>
                  ))}</tbody>
                </table>
              </div>
            ) : <EmptyState title="Sin mediciones" description="No hay sensor logs para la sesión y el rango de fechas seleccionados." />}
          </SectionCard>
        </div>
      </div>

      <SectionCard title="Resumen por sensor" description="Resultado de GET /api/telemetry/summary para el paciente y rango seleccionados" action={<Badge tone="info">Agregación MongoDB</Badge>}>
        {summary.length ? <div className="summary-grid">
          {summary.map((item) => (
            <article className="summary-card" key={`${item.sensorType}-${item.unit}`}>
              <div className="summary-card__heading"><span><Activity size={17} /></span><div><strong>{sensorNames[item.sensorType] || item.sensorType}</strong><small>{item.unit}</small></div></div>
              <dl><div><dt>Promedio</dt><dd>{item.average}</dd></div><div><dt>Mínimo</dt><dd>{item.minimum}</dd></div><div><dt>Máximo</dt><dd>{item.maximum}</dd></div><div><dt>Cantidad</dt><dd>{item.sampleCount}</dd></div></dl>
            </article>
          ))}
        </div> : <EmptyState title="Sin resumen disponible" description="No existen mediciones agregables en el rango seleccionado." />}
      </SectionCard>
    </div>
  );
}

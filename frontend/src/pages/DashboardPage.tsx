import {
  Activity,
  ArrowRight,
  CheckCircle2,
  Clock3,
  Database,
  HardDrive,
  HeartPulse,
  Network,
  RefreshCw,
  Server,
  ShieldCheck,
  TriangleAlert,
  UsersRound,
  WifiOff,
} from "lucide-react";
import { Link } from "react-router";
import { Badge } from "../components/ui/Badge";
import { Button } from "../components/ui/Button";
import { ErrorState, LoadingState } from "../components/ui/States";
import { PageHeader } from "../components/ui/PageHeader";
import { SectionCard } from "../components/ui/SectionCard";
import { useApi } from "../hooks/useApi";
import { api } from "../lib/api";

type DashboardData = {
  active_connections: number;
  database_name: string;
  database_size_bytes: number;
  in_recovery: boolean;
  observed_at: string;
  source: string;
};

type ServiceHealth = {
  status?: string;
};

type DatabaseHealth = ServiceHealth & {
  in_recovery?: boolean | null;
  inRecovery?: boolean | null;
};

type DatabasesHealth = ServiceHealth & {
  primary?: DatabaseHealth;
  replica?: DatabaseHealth;
};

type MongoHealth = ServiceHealth & {
  database?: string;
  provider?: string;
};

type InfrastructureStatus = {
  mongodb?: MongoHealth;
  primary?: DatabaseHealth;
  replica?: DatabaseHealth;
};

type DashboardOverview = {
  apiAvailable: boolean;
  dashboard: DashboardData;
  databases?: DatabasesHealth;
  infrastructure?: InfrastructureStatus;
  mongodb?: MongoHealth;
};

type VisualStatus = "healthy" | "degraded" | "offline";

function visualStatus(value?: string): VisualStatus {
  if (value === "healthy") return "healthy";
  if (["unhealthy", "offline", "unavailable"].includes(value ?? "")) return "offline";
  return "degraded";
}

function statusLabel(status: VisualStatus) {
  return { healthy: "Healthy", degraded: "Degraded", offline: "Offline" }[status];
}

function settledValue<T>(result: PromiseSettledResult<{ data: T }>) {
  return result.status === "fulfilled" ? result.value.data : undefined;
}

async function loadDashboard(signal: AbortSignal): Promise<DashboardOverview> {
  const [healthResult, databasesResult, dashboardResult, mongodbResult, infrastructureResult] =
    await Promise.allSettled([
      api.getResult<ServiceHealth>("/health", signal),
      api.getResult<DatabasesHealth>("/health/databases", signal),
      api.getResult<DashboardData>("/dashboard", signal),
      api.getResult<MongoHealth>("/api/mongodb/health", signal),
      api.getResult<InfrastructureStatus>("/api/infrastructure/status", signal),
    ]);

  if (dashboardResult.status === "rejected") throw dashboardResult.reason;
  if (!dashboardResult.value.ok) {
    throw new Error("La lectura del dashboard desde PostgreSQL Replica no está disponible.");
  }

  const health = settledValue(healthResult);
  const infrastructure =
    infrastructureResult.status === "fulfilled" && infrastructureResult.value.status !== 404
      ? infrastructureResult.value.data
      : undefined;

  return {
    apiAvailable: healthResult.status === "fulfilled" && health?.status === "healthy",
    dashboard: dashboardResult.value.data,
    databases: settledValue(databasesResult),
    infrastructure,
    mongodb: settledValue(mongodbResult),
  };
}

function formatBytes(bytes: number) {
  if (!Number.isFinite(bytes) || bytes <= 0) return "0 MB";
  const units = ["B", "KB", "MB", "GB", "TB"];
  const index = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
  return `${(bytes / 1024 ** index).toFixed(index > 2 ? 1 : 0)} ${units[index]}`;
}

function formatObservedAt(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Actualizado recientemente";
  return new Intl.DateTimeFormat("es-CR", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

const moduleLinks = [
  {
    title: "Personal clínico",
    description: "Directorio profesional y especialidades",
    icon: UsersRound,
    path: "/staff",
    tone: "teal",
  },
  {
    title: "Expedientes",
    description: "Documentos clínicos validados",
    icon: ShieldCheck,
    path: "/clinical-records",
    tone: "blue",
  },
  {
    title: "Telemetría",
    description: "Sesiones y señales biomédicas",
    icon: Activity,
    path: "/telemetry",
    tone: "green",
  },
  {
    title: "Distribución",
    description: "Fragmentación y coordinadores",
    icon: Network,
    path: "/distribution",
    tone: "navy",
  },
];

export function DashboardPage() {
  const { data, error, isLoading, retry } = useApi<DashboardOverview>(loadDashboard);

  const primaryHealth = data?.infrastructure?.primary ?? data?.databases?.primary;
  const replicaHealth = data?.infrastructure?.replica ?? data?.databases?.replica;
  const mongoHealth = data?.mongodb?.status ? data.mongodb : data?.infrastructure?.mongodb;
  const primaryStatus = visualStatus(primaryHealth?.status);
  const replicaStatus = data
    ? visualStatus(replicaHealth?.status ?? (data.dashboard.source === "replica" ? "healthy" : undefined))
    : "degraded";
  const mongoStatus = visualStatus(mongoHealth?.status);
  const platformStatus: VisualStatus =
    primaryStatus === "healthy" && replicaStatus === "healthy" && mongoStatus === "healthy" && data?.apiAvailable
      ? "healthy"
      : data
        ? "degraded"
        : error
          ? "offline"
          : "degraded";

  return (
    <div className="page-stack">
      <PageHeader
        actions={<Button icon={RefreshCw} isLoading={isLoading} onClick={retry} variant="secondary">Actualizar</Button>}
        description="Disponibilidad, replicación y métricas operativas del ecosistema de datos."
        eyebrow="CENTRO DE OPERACIONES"
        title="Buenos días, equipo"
      />

      <section className="welcome-panel" aria-labelledby="platform-status-title">
        <div className="welcome-panel__content">
          <div className={`welcome-panel__status status-text--${platformStatus}`}>
            <span aria-hidden="true" />
            PLATAFORMA {statusLabel(platformStatus).toUpperCase()}
          </div>
          <h2 id="platform-status-title">Operación clínica respaldada<br />por datos resilientes.</h2>
          <p>La lectura del panel se mantiene disponible desde Replica aunque PostgreSQL Primary esté fuera de línea.</p>
        </div>
        <div className="welcome-panel__visual" aria-hidden="true">
          <div className="pulse-orbit pulse-orbit--outer" />
          <div className="pulse-orbit pulse-orbit--inner" />
          <div className="pulse-core"><Activity size={31} /></div>
        </div>
      </section>

      {isLoading && !data ? <LoadingState label="Consultando infraestructura de datos" /> : null}
      {error ? <ErrorState message={error.message} onRetry={retry} /> : null}

      {data ? (
        <>
          <section className="infrastructure-grid" aria-label="Estado de bases de datos">
            <InfrastructureCard
              detail="Nodo de escritura"
              icon={Database}
              label="PostgreSQL Primary"
              status={primaryStatus}
              supportingText={primaryStatus === "offline" ? "Escrituras no disponibles" : "Aceptando escrituras"}
            />
            <InfrastructureCard
              detail="Nodo de lectura"
              icon={Server}
              label="PostgreSQL Replica"
              status={replicaStatus}
              supportingText={data.dashboard.in_recovery ? "En modo recovery" : "Revisar rol del nodo"}
            />
            <InfrastructureCard
              detail={`Provider: ${mongoHealth?.provider ?? "no disponible"}`}
              icon={HardDrive}
              label="MongoDB"
              status={mongoStatus}
              supportingText={mongoHealth?.database ?? "Datos clínicos documentales"}
            />
          </section>

          <section className="replication-panel" aria-label="Flujo de replicación PostgreSQL">
            <div className="replication-panel__copy">
              <span className="replica-source-badge"><CheckCircle2 size={14} /> Consultas servidas por Replica</span>
              <h2>Flujo de replicación</h2>
              <p>Streaming asíncrono de cambios mediante Write-Ahead Log.</p>
            </div>
            <div className="replication-flow">
              <FlowNode label="Primary" status={primaryStatus} />
              <div className="replication-flow__connector"><span>WAL</span><ArrowRight size={20} /></div>
              <FlowNode label="Replica" status={replicaStatus} />
            </div>
          </section>

          <div className="overview-grid">
            <SectionCard
              action={<Badge tone="success">Fuente: Replica</Badge>}
              description="Métricas consultadas exclusivamente en el nodo de lectura"
              title="Métricas del dashboard"
            >
              <div className="metric-grid">
                <article className="metric">
                  <span className="metric__icon"><Database aria-hidden="true" size={20} /></span>
                  <div><span>Base de datos</span><strong>{data.dashboard.database_name}</strong></div>
                </article>
                <article className="metric">
                  <span className="metric__icon"><HardDrive aria-hidden="true" size={20} /></span>
                  <div><span>Almacenamiento</span><strong>{formatBytes(data.dashboard.database_size_bytes)}</strong></div>
                </article>
                <article className="metric">
                  <span className="metric__icon"><Server aria-hidden="true" size={20} /></span>
                  <div><span>Conexiones activas</span><strong>{data.dashboard.active_connections}</strong></div>
                </article>
              </div>
              <div className="observed-time">
                <Clock3 aria-hidden="true" size={15} />
                <span>{formatObservedAt(data.dashboard.observed_at)}</span>
              </div>
            </SectionCard>

            <SectionCard description="Accede rápidamente a cada área" title="Módulos principales">
              <div className="module-list">
                {moduleLinks.map(({ description, icon: Icon, path, title, tone }) => (
                  <Link className="module-link" key={path} to={path}>
                    <span className={`module-link__icon module-link__icon--${tone}`}>
                      <Icon aria-hidden="true" size={19} />
                    </span>
                    <span className="module-link__text"><strong>{title}</strong><small>{description}</small></span>
                    <ArrowRight aria-hidden="true" size={17} />
                  </Link>
                ))}
              </div>
            </SectionCard>
          </div>
        </>
      ) : null}
    </div>
  );
}

type InfrastructureCardProps = {
  detail: string;
  icon: typeof Database;
  label: string;
  status: VisualStatus;
  supportingText: string;
};

function InfrastructureCard({ detail, icon: Icon, label, status, supportingText }: InfrastructureCardProps) {
  const StatusIcon = status === "healthy" ? CheckCircle2 : status === "offline" ? WifiOff : TriangleAlert;
  return (
    <article className={`infrastructure-card infrastructure-card--${status}`}>
      <div className="infrastructure-card__top">
        <span className="infrastructure-card__icon"><Icon aria-hidden="true" size={22} /></span>
        <span className={`health-indicator health-indicator--${status}`}><StatusIcon size={13} />{statusLabel(status)}</span>
      </div>
      <p>{detail}</p>
      <h2>{label}</h2>
      <small>{supportingText}</small>
    </article>
  );
}

function FlowNode({ label, status }: { label: string; status: VisualStatus }) {
  return (
    <div className={`flow-node flow-node--${status}`}>
      <HeartPulse aria-hidden="true" size={18} />
      <strong>{label}</strong>
      <span>{statusLabel(status)}</span>
    </div>
  );
}

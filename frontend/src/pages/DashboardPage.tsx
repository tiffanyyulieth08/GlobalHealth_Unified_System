import {
  Activity,
  ArrowRight,
  Clock3,
  Database,
  HardDrive,
  Network,
  RefreshCw,
  Server,
  ShieldCheck,
  UsersRound,
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
  const { data, error, isLoading, retry } = useApi<DashboardData>((signal) =>
    api.get("/dashboard", signal),
  );

  return (
    <div className="page-stack">
      <PageHeader
        actions={<Button icon={RefreshCw} onClick={retry} variant="secondary">Actualizar</Button>}
        description="Una vista clara del entorno clínico y la infraestructura de datos."
        eyebrow="CENTRO DE OPERACIONES"
        title="Buenos días, equipo"
      />

      <section className="welcome-panel" aria-labelledby="platform-status-title">
        <div className="welcome-panel__content">
          <div className="welcome-panel__status">
            <span aria-hidden="true" />
            PLATAFORMA UNIFICADA
          </div>
          <h2 id="platform-status-title">Información clínica conectada,<br />decisiones mejor informadas.</h2>
          <p>Supervisa la operación y accede a cada dominio de datos desde un entorno seguro.</p>
        </div>
        <div className="welcome-panel__visual" aria-hidden="true">
          <div className="pulse-orbit pulse-orbit--outer" />
          <div className="pulse-orbit pulse-orbit--inner" />
          <div className="pulse-core"><Activity size={31} /></div>
        </div>
      </section>

      <div className="overview-grid">
        <SectionCard
          action={<Badge tone={error ? "neutral" : "success"}>{error ? "Sin conexión" : "En línea"}</Badge>}
          description="Lectura actual desde PostgreSQL Replica"
          title="Estado de la plataforma"
        >
          {isLoading ? <LoadingState label="Consultando infraestructura" /> : null}
          {error ? <ErrorState message={error.message} onRetry={retry} /> : null}
          {data && !isLoading ? (
            <div className="metric-grid">
              <article className="metric">
                <span className="metric__icon"><Database aria-hidden="true" size={20} /></span>
                <div><span>Base de datos</span><strong>{data.database_name}</strong></div>
              </article>
              <article className="metric">
                <span className="metric__icon"><HardDrive aria-hidden="true" size={20} /></span>
                <div><span>Almacenamiento</span><strong>{formatBytes(data.database_size_bytes)}</strong></div>
              </article>
              <article className="metric">
                <span className="metric__icon"><Server aria-hidden="true" size={20} /></span>
                <div><span>Conexiones activas</span><strong>{data.active_connections}</strong></div>
              </article>
            </div>
          ) : null}
          <div className="observed-time">
            <Clock3 aria-hidden="true" size={15} />
            <span>{data ? formatObservedAt(data.observed_at) : "Esperando actualización"}</span>
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
    </div>
  );
}

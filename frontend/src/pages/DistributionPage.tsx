import { Database, GitMerge, Layers3, MapPin, ShieldCheck, WalletCards } from "lucide-react";
import { Badge } from "../components/ui/Badge";
import { PageHeader } from "../components/ui/PageHeader";
import { SectionCard } from "../components/ui/SectionCard";
import { EmptyState, ErrorState, LoadingState } from "../components/ui/States";
import { useApi } from "../hooks/useApi";
import { api } from "../lib/api";

type HorizontalPatient = {
  patientId: number;
  fullName: string;
  phone: string;
  email: string;
  address: string;
  region: "NORTH" | "SOUTH";
};

type HorizontalData = { count: number; patients: HorizontalPatient[]; view: string };
type HorizontalSummary = { total: number; regions: { NORTH: number; SOUTH: number } };

type VerticalPatient = {
  patientId: number;
  fullName: string;
  phone: string;
  email: string;
  address: string;
  emergencyContact: string;
  insuranceProvider: string;
  insuranceNumber: string;
  billingStatus: string;
  outstandingBalance: number;
  paymentMethod: string;
};

type VerticalData = { count: number; patients: VerticalPatient[]; view: string };
type VerticalSummary = { reconstructedPatients: number };

type DistributionData = {
  horizontal: HorizontalData;
  horizontalSummary: HorizontalSummary;
  vertical: VerticalData;
  verticalSummary: VerticalSummary;
};

const decimal = new Intl.NumberFormat("es-CR", {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

export function DistributionPage() {
  const { data, error, isLoading, retry } = useApi<DistributionData>(async (signal) => {
    const [horizontal, horizontalSummary, vertical, verticalSummary] = await Promise.all([
      api.get<HorizontalData>("/api/fragmentation/horizontal?limit=500", signal),
      api.get<HorizontalSummary>("/api/fragmentation/horizontal/summary", signal),
      api.get<VerticalData>("/api/fragmentation/vertical?limit=500", signal),
      api.get<VerticalSummary>("/api/fragmentation/vertical/summary", signal),
    ]);
    return { horizontal, horizontalSummary, vertical, verticalSummary };
  });

  return (
    <div className="page-stack distribution-page">
      <PageHeader
        eyebrow="ARQUITECTURA DE DATOS"
        title="Distribución y fragmentación"
        description="Vista demostrativa de cómo PostgreSQL distribuye y reconstruye los datos mediante tablas foráneas y coordinadores."
        actions={<div className="technology-badges"><Badge>PostgreSQL</Badge><Badge tone="info">postgres_fdw</Badge></div>}
      />

      {isLoading ? <LoadingState label="Consultando coordinadores de fragmentación" /> : null}
      {error ? <ErrorState message={error.message} onRetry={retry} /> : null}

      {data ? <>
        <SectionCard
          title="Fragmentación horizontal por región"
          description="Cada fila completa vive en NORTH o SOUTH; el coordinador consulta ambos fragmentos."
          action={<Badge tone="info">UNION ALL</Badge>}
        >
          <div className="reconstruction-flow">
            <div className="fragment-node fragment-node--north"><MapPin size={19} /><span><small>Fragmento</small><strong>NORTH</strong></span><b>{data.horizontalSummary.regions.NORTH}</b></div>
            <div className="fragment-node fragment-node--south"><MapPin size={19} /><span><small>Fragmento</small><strong>SOUTH</strong></span><b>{data.horizontalSummary.regions.SOUTH}</b></div>
            <div className="reconstruction-operator"><Badge tone="info">UNION ALL</Badge><span>reconstruye</span></div>
            <div className="fragment-node fragment-node--result"><Database size={19} /><span><small>Vista global</small><strong>patients_all</strong></span><b>{data.horizontalSummary.total}</b></div>
          </div>
          {data.horizontal.patients.length ? <div className="fragment-columns">
            {(["NORTH", "SOUTH"] as const).map((region) => <div className={`region-panel region-panel--${region.toLowerCase()}`} key={region}>
              <div className="region-panel__header"><div><span>Fragmento regional</span><h3>{region}</h3></div><Badge>{data.horizontalSummary.regions[region]} filas</Badge></div>
              <div className="compact-records">{data.horizontal.patients.filter((patient) => patient.region === region).map((patient) => <article key={patient.patientId}><strong>{patient.fullName}</strong><span>patient_id: {patient.patientId}</span><small>{patient.email}</small><small>{patient.address}</small></article>)}</div>
            </div>)}
          </div> : <EmptyState title="Sin filas horizontales" description="La vista patients_all no devolvió pacientes." />}
          <p className="technical-note"><GitMerge size={16} /><span><strong>Reconstrucción global:</strong> <code>patients_north UNION ALL patients_south</code>. Se preservan todas las filas de ambos fragmentos.</span></p>
        </SectionCard>

        <SectionCard
          title="Fragmentación vertical por dominio"
          description="Los atributos públicos y financieros permanecen separados y se reconstruyen con su clave común."
          action={<Badge tone="info">JOIN</Badge>}
        >
          <div className="vertical-explanation">
            <div className="vertical-source vertical-source--public"><ShieldCheck size={22} /><div><small>Tabla foránea pública</small><strong>patients_public</strong><span>Identidad, contacto, dirección y contacto de emergencia</span></div></div>
            <div className="vertical-key"><code>patient_id</code><Badge tone="info">JOIN</Badge></div>
            <div className="vertical-source vertical-source--financial"><WalletCards size={22} /><div><small>Tabla foránea financiera</small><strong>patients_financial</strong><span>Seguro, facturación, saldo y método de pago</span></div></div>
            <div className="vertical-result"><Layers3 size={21} /><div><small>Vista reconstruida</small><strong>patients_full</strong></div><Badge tone="success">{data.verticalSummary.reconstructedPatients} pacientes</Badge></div>
          </div>

          {data.vertical.patients.length ? <div className="vertical-records">{data.vertical.patients.map((patient) => <article className="vertical-record" key={patient.patientId}>
            <header><div><span>patient_id: {patient.patientId}</span><h3>{patient.fullName}</h3></div><Badge>{patient.billingStatus}</Badge></header>
            <div className="vertical-record__domains">
              <section className="domain-public"><h4><ShieldCheck size={15} /> Datos públicos</h4><dl><div><dt>Teléfono</dt><dd>{patient.phone}</dd></div><div><dt>Correo</dt><dd>{patient.email}</dd></div><div><dt>Dirección</dt><dd>{patient.address}</dd></div><div><dt>Emergencia</dt><dd>{patient.emergencyContact}</dd></div></dl></section>
              <section className="domain-financial"><h4><WalletCards size={15} /> Datos financieros</h4><dl><div><dt>Aseguradora</dt><dd>{patient.insuranceProvider}</dd></div><div><dt>Póliza</dt><dd>{patient.insuranceNumber}</dd></div><div><dt>Saldo</dt><dd>{decimal.format(patient.outstandingBalance)}</dd></div><div><dt>Pago</dt><dd>{patient.paymentMethod}</dd></div></dl></section>
            </div>
          </article>)}</div> : <EmptyState title="Sin filas verticales" description="La vista patients_full no devolvió pacientes reconstruidos." />}
          <p className="technical-note"><GitMerge size={16} /><span><strong>Reconstrucción vertical:</strong> <code>patients_public JOIN patients_financial USING (patient_id)</code>.</span></p>
        </SectionCard>
      </> : null}
    </div>
  );
}

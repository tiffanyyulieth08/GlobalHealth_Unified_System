import { Database, GitBranch, Network, PanelsTopLeft } from "lucide-react";
import { ModuleShell } from "../components/modules/ModuleShell";

export function DistributionPage() {
  return (
    <ModuleShell
      capabilities={[
        { label: "Fragmentación horizontal", description: "Distribución regional de información clínica.", icon: GitBranch },
        { label: "Fragmentación vertical", description: "Separación controlada por dominio de datos.", icon: PanelsTopLeft },
        { label: "Coordinadores", description: "Estado unificado de los nodos de consulta.", icon: Network },
      ]}
      description="Observa la distribución de datos entre nodos y el estado de sus coordinadores de consulta."
      emptyDescription="Los resúmenes de fragmentación aparecerán aquí al cargar información desde FastAPI."
      emptyTitle="No hay eventos de distribución"
      eyebrow="ARQUITECTURA DE DATOS"
      icon={Database}
      title="Distribución"
    />
  );
}

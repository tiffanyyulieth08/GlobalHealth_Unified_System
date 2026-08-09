import { FileCheck2, FileSearch, Files, ShieldCheck } from "lucide-react";
import { ModuleShell } from "../components/modules/ModuleShell";

export function ClinicalRecordsPage() {
  return (
    <ModuleShell
      capabilities={[
        { label: "Expedientes XML", description: "Documentos clínicos estructurados y versionados.", icon: Files },
        { label: "Validación XSD", description: "Verificación de estructura antes de persistir.", icon: FileCheck2 },
        { label: "Consulta clínica", description: "Búsqueda segura de hallazgos y diagnósticos.", icon: FileSearch },
      ]}
      description="Consulta y gestiona expedientes clínicos estructurados con validación de esquema y trazabilidad."
      emptyDescription="Los documentos validados se mostrarán aquí al habilitar la integración XML/XSD de FastAPI."
      emptyTitle="No hay expedientes recientes"
      eyebrow="INFORMACIÓN CLÍNICA"
      icon={ShieldCheck}
      title="Expedientes clínicos"
    />
  );
}

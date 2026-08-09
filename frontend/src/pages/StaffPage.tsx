import { BadgeCheck, ContactRound, Stethoscope, UserRoundSearch } from "lucide-react";
import { ModuleShell } from "../components/modules/ModuleShell";

export function StaffPage() {
  return (
    <ModuleShell
      capabilities={[
        { label: "Directorio clínico", description: "Perfiles, contacto y datos profesionales.", icon: ContactRound },
        { label: "Especialidades", description: "Áreas de atención y capacidades médicas.", icon: Stethoscope },
        { label: "Credenciales", description: "Estado y trazabilidad del personal autorizado.", icon: BadgeCheck },
      ]}
      description="Administra el directorio de profesionales, especialidades y datos de contacto desde un único lugar."
      emptyDescription="Los perfiles profesionales se mostrarán aquí al conectar las operaciones MOR de FastAPI."
      emptyTitle="Aún no hay personal para mostrar"
      eyebrow="GESTIÓN DE PERSONAS"
      icon={UserRoundSearch}
      title="Personal clínico"
    />
  );
}

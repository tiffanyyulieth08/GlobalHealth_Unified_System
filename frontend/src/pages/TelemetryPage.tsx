import { Activity, HeartPulse, Radio, Waves } from "lucide-react";
import { ModuleShell } from "../components/modules/ModuleShell";

export function TelemetryPage() {
  return (
    <ModuleShell
      capabilities={[
        { label: "Sesiones activas", description: "Seguimiento de monitoreos clínicos en curso.", icon: Radio },
        { label: "Señales vitales", description: "Lecturas capturadas desde sensores médicos.", icon: HeartPulse },
        { label: "Tendencias", description: "Resumen longitudinal de métricas relevantes.", icon: Activity },
      ]}
      description="Supervisa sesiones, señales biomédicas y tendencias capturadas por dispositivos conectados."
      emptyDescription="Las mediciones aparecerán aquí cuando existan sesiones de telemetría disponibles en la API."
      emptyTitle="Sin actividad de telemetría"
      eyebrow="MONITOREO REMOTO"
      icon={Waves}
      title="Telemetría médica"
    />
  );
}

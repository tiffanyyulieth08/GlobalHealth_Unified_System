import type { LucideIcon } from "lucide-react";
import { Badge } from "../ui/Badge";
import { EmptyState } from "../ui/States";
import { PageHeader } from "../ui/PageHeader";
import { SectionCard } from "../ui/SectionCard";

type Capability = {
  description: string;
  icon: LucideIcon;
  label: string;
};

type ModuleShellProps = {
  capabilities: Capability[];
  description: string;
  emptyDescription: string;
  emptyTitle: string;
  eyebrow: string;
  icon: LucideIcon;
  title: string;
};

export function ModuleShell({
  capabilities,
  description,
  emptyDescription,
  emptyTitle,
  eyebrow,
  icon: EmptyIcon,
  title,
}: ModuleShellProps) {
  return (
    <div className="page-stack">
      <PageHeader
        description={description}
        eyebrow={eyebrow}
        title={title}
      />

      <div className="capability-grid" aria-label="Capacidades del módulo">
        {capabilities.map(({ description: itemDescription, icon: Icon, label }) => (
          <article className="capability-card" key={label}>
            <span className="capability-card__icon"><Icon aria-hidden="true" size={20} /></span>
            <div>
              <div className="capability-card__heading">
                <h2>{label}</h2>
                <Badge tone="info">Preparado</Badge>
              </div>
              <p>{itemDescription}</p>
            </div>
          </article>
        ))}
      </div>

      <SectionCard title="Actividad reciente" description="Los datos aparecerán aquí cuando el módulo esté habilitado.">
        <EmptyState
          description={emptyDescription}
          icon={EmptyIcon}
          title={emptyTitle}
        />
      </SectionCard>
    </div>
  );
}

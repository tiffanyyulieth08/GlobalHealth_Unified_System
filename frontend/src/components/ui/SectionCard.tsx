import type { ReactNode } from "react";

type SectionCardProps = {
  action?: ReactNode;
  children: ReactNode;
  description?: string;
  title: string;
};

export function SectionCard({ action, children, description, title }: SectionCardProps) {
  return (
    <section className="section-card">
      <div className="section-card__header">
        <div>
          <h2>{title}</h2>
          {description ? <p>{description}</p> : null}
        </div>
        {action}
      </div>
      {children}
    </section>
  );
}

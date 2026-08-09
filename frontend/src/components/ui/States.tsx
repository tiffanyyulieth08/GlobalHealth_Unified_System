import { AlertCircle, Inbox, RotateCcw } from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { Button } from "./Button";

export function LoadingState({ label = "Cargando información" }: { label?: string }) {
  return (
    <div className="state state--loading" role="status" aria-live="polite">
      <div className="state__pulse" aria-hidden="true" />
      <div>
        <p className="state__title">{label}</p>
        <p className="state__text">Esto tomará solo un momento.</p>
      </div>
    </div>
  );
}

type ErrorStateProps = {
  message?: string;
  onRetry?: () => void;
};

export function ErrorState({
  message = "Ocurrió un problema al cargar la información.",
  onRetry,
}: ErrorStateProps) {
  return (
    <div className="state state--error" role="alert">
      <span className="state__icon"><AlertCircle aria-hidden="true" size={22} /></span>
      <div className="state__content">
        <p className="state__title">No pudimos cargar los datos</p>
        <p className="state__text">{message}</p>
      </div>
      {onRetry ? (
        <Button icon={RotateCcw} onClick={onRetry} variant="secondary">
          Reintentar
        </Button>
      ) : null}
    </div>
  );
}

type EmptyStateProps = {
  action?: React.ReactNode;
  description: string;
  icon?: LucideIcon;
  title: string;
};

export function EmptyState({
  action,
  description,
  icon: Icon = Inbox,
  title,
}: EmptyStateProps) {
  return (
    <div className="empty-state">
      <span className="empty-state__icon"><Icon aria-hidden="true" size={25} /></span>
      <h3>{title}</h3>
      <p>{description}</p>
      {action ? <div className="empty-state__action">{action}</div> : null}
    </div>
  );
}

import { LoaderCircle, type LucideIcon } from "lucide-react";
import type { ButtonHTMLAttributes } from "react";

type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> & {
  icon?: LucideIcon;
  isLoading?: boolean;
  variant?: "primary" | "secondary" | "ghost";
};

export function Button({
  children,
  className = "",
  disabled,
  icon: Icon,
  isLoading = false,
  type = "button",
  variant = "primary",
  ...props
}: ButtonProps) {
  return (
    <button
      className={`button button--${variant} ${className}`.trim()}
      disabled={disabled || isLoading}
      type={type}
      {...props}
    >
      {isLoading ? (
        <LoaderCircle className="button__spinner" aria-hidden="true" size={17} />
      ) : Icon ? (
        <Icon aria-hidden="true" size={17} />
      ) : null}
      <span>{isLoading ? "Procesando…" : children}</span>
    </button>
  );
}

import {
  Activity,
  Files,
  LayoutDashboard,
  Network,
  UsersRound,
  X,
} from "lucide-react";
import { NavLink } from "react-router";
import { BrandMark } from "./BrandMark";

const navigation = [
  { label: "Vista general", path: "/", icon: LayoutDashboard, end: true },
  { label: "Personal", path: "/staff", icon: UsersRound },
  { label: "Expedientes", path: "/clinical-records", icon: Files },
  { label: "Telemetría", path: "/telemetry", icon: Activity },
  { label: "Distribución", path: "/distribution", icon: Network },
];

type SidebarProps = {
  isOpen: boolean;
  onClose: () => void;
};

export function Sidebar({ isOpen, onClose }: SidebarProps) {
  return (
    <>
      <div
        className={`sidebar-backdrop ${isOpen ? "is-visible" : ""}`}
        onClick={onClose}
        aria-hidden="true"
      />
      <aside className={`sidebar ${isOpen ? "is-open" : ""}`} aria-label="Navegación principal">
        <div className="sidebar__header">
          <NavLink className="brand" to="/" onClick={onClose} aria-label="GlobalHealth, inicio">
            <BrandMark />
            <span className="brand__text">
              <strong>GlobalHealth</strong>
              <small>Unified System</small>
            </span>
          </NavLink>
          <button className="icon-button sidebar__close" onClick={onClose} aria-label="Cerrar menú">
            <X aria-hidden="true" size={20} />
          </button>
        </div>

        <nav className="sidebar__nav">
          <p className="sidebar__label">ESPACIO DE TRABAJO</p>
          {navigation.map(({ end, icon: Icon, label, path }) => (
            <NavLink
              className={({ isActive }) => `nav-item ${isActive ? "is-active" : ""}`}
              end={end}
              key={path}
              onClick={onClose}
              to={path}
            >
              <Icon aria-hidden="true" size={19} strokeWidth={1.8} />
              <span>{label}</span>
            </NavLink>
          ))}
        </nav>

        <div className="sidebar__footer">
          <div className="system-card">
            <span className="system-card__indicator" aria-hidden="true" />
            <div>
              <strong>Sistema operativo</strong>
              <span>Servicios supervisados</span>
            </div>
          </div>
          <p>GlobalHealth v0.1</p>
        </div>
      </aside>
    </>
  );
}

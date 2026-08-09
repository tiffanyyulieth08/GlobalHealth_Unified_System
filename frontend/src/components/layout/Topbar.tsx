import { Bell, Menu, Search } from "lucide-react";

type TopbarProps = {
  onMenuOpen: () => void;
};

export function Topbar({ onMenuOpen }: TopbarProps) {
  return (
    <header className="topbar">
      <button className="icon-button topbar__menu" onClick={onMenuOpen} aria-label="Abrir menú">
        <Menu aria-hidden="true" size={21} />
      </button>

      <label className="search-field">
        <Search aria-hidden="true" size={18} />
        <span className="sr-only">Buscar en GlobalHealth</span>
        <input type="search" placeholder="Buscar pacientes, personal…" />
        <kbd>⌘ K</kbd>
      </label>

      <div className="topbar__actions">
        <button className="icon-button notification-button" aria-label="Notificaciones">
          <Bell aria-hidden="true" size={19} />
          <span aria-hidden="true" />
        </button>
        <div className="topbar__divider" />
        <button className="profile-button" aria-label="Abrir menú de usuario">
          <span className="profile-button__avatar" aria-hidden="true">GH</span>
          <span className="profile-button__info">
            <strong>Administración</strong>
            <small>Operaciones clínicas</small>
          </span>
        </button>
      </div>
    </header>
  );
}

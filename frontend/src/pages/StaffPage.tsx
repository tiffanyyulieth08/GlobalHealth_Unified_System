import { useEffect, useMemo, useState, type FormEvent } from "react";
import {
  Building2, Mail, MapPin, Phone as PhoneIcon, Plus, Search, Stethoscope,
  Trash2, UserRound, Wrench, X,
} from "lucide-react";
import { Badge } from "../components/ui/Badge";
import { Button } from "../components/ui/Button";
import { EmptyState, ErrorState, LoadingState } from "../components/ui/States";
import { PageHeader } from "../components/ui/PageHeader";
import { api } from "../lib/api";

type Phone = { country_code: string | null; number: string | null; kind: string | null };
type Equipment = { brand: string | null; model: string | null; serial_number: string | null; status: string | null };
type Address = { street: string | null; city: string | null; state: string | null; zip: string | null; country: string | null };
type Clinic = { id: number; name: string; address: Address | null; equipments: Equipment[] | null };
type Doctor = {
  id: number; first_name: string; last_name: string; email: string; hire_date: string | null;
  address: Address | null; phone: Phone | null; salary: number | null; specialty: string;
  license: string; specialties: string[] | null; clinic_id: number | null; phone_numbers: Phone[] | null;
};
type DoctorForm = { first_name: string; last_name: string; email: string; hire_date: string; salary: string; specialty: string; license: string; clinic_id: string };

const emptyForm: DoctorForm = { first_name: "", last_name: "", email: "", hire_date: "", salary: "", specialty: "", license: "", clinic_id: "" };

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : "No se pudo completar la operación.";
}

export function StaffPage() {
  const [doctors, setDoctors] = useState<Doctor[]>([]);
  const [clinics, setClinics] = useState<Clinic[]>([]);
  const [selected, setSelected] = useState<Doctor | null>(null);
  const [form, setForm] = useState<DoctorForm>(emptyForm);
  const [mode, setMode] = useState<"create" | "edit" | null>(null);
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [specialty, setSpecialty] = useState("");
  const [phone, setPhone] = useState({ country_code: "+506", number: "", kind: "Móvil" });

  async function load() {
    setLoading(true);
    setError("");
    try {
      const [doctorData, clinicData] = await Promise.all([
        api.get<Doctor[]>("/api/mor/doctors"),
        api.get<Clinic[]>("/api/mor/clinics"),
      ]);
      setDoctors(doctorData);
      setClinics(clinicData);
    } catch (requestError) {
      setError(errorMessage(requestError));
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { void load(); }, []);

  const filtered = useMemo(() => {
    const value = query.trim().toLocaleLowerCase();
    if (!value) return doctors;
    return doctors.filter((doctor) =>
      `${doctor.first_name} ${doctor.last_name} ${doctor.specialty} ${doctor.license}`.toLocaleLowerCase().includes(value),
    );
  }, [doctors, query]);

  const selectedClinic = selected ? clinics.find((clinic) => clinic.id === selected.clinic_id) : undefined;

  async function openDetail(id: number) {
    setError("");
    try {
      setSelected(await api.get<Doctor>(`/api/mor/doctors/${id}`));
    } catch (requestError) { setError(errorMessage(requestError)); }
  }

  function openCreate() {
    setForm(emptyForm);
    setMode("create");
  }

  function openEdit() {
    if (!selected) return;
    setForm({
      first_name: selected.first_name, last_name: selected.last_name, email: selected.email,
      hire_date: selected.hire_date ?? "", salary: selected.salary?.toString() ?? "",
      specialty: selected.specialty, license: selected.license, clinic_id: selected.clinic_id?.toString() ?? "",
    });
    setMode("edit");
  }

  async function saveDoctor(event: FormEvent) {
    event.preventDefault();
    setSaving(true);
    setError("");
    const payload = {
      ...form,
      hire_date: form.hire_date || null,
      salary: form.salary ? Number(form.salary) : null,
      clinic_id: form.clinic_id ? Number(form.clinic_id) : null,
    };
    try {
      const saved = mode === "edit" && selected
        ? await api.patch<Doctor>(`/api/mor/doctors/${selected.id}`, payload)
        : await api.post<Doctor>("/api/mor/doctors", payload);
      setMode(null);
      setSelected(saved);
      setNotice(mode === "edit" ? "Datos del médico actualizados." : "Médico registrado correctamente.");
      await load();
    } catch (requestError) { setError(errorMessage(requestError)); }
    finally { setSaving(false); }
  }

  async function removeDoctor() {
    if (!selected || !window.confirm(`¿Eliminar a ${selected.first_name} ${selected.last_name}? Esta acción no se puede deshacer.`)) return;
    try {
      await api.delete<Doctor>(`/api/mor/doctors/${selected.id}`);
      setSelected(null);
      setNotice("Médico eliminado.");
      await load();
    } catch (requestError) { setError(errorMessage(requestError)); }
  }

  async function mutateDetail(request: Promise<unknown>, message: string) {
    if (!selected) return;
    setSaving(true);
    setError("");
    try {
      await request;
      await openDetail(selected.id);
      await load();
      setNotice(message);
    } catch (requestError) { setError(errorMessage(requestError)); }
    finally { setSaving(false); }
  }

  async function addSpecialty(event: FormEvent) {
    event.preventDefault();
    if (!selected || !specialty.trim()) return;
    await mutateDetail(api.post(`/api/mor/doctors/${selected.id}/specialties`, { specialty: specialty.trim() }), "Especialidad agregada.");
    setSpecialty("");
  }

  async function addPhone(event: FormEvent) {
    event.preventDefault();
    if (!selected || !phone.number.trim()) return;
    await mutateDetail(api.post(`/api/mor/doctors/${selected.id}/phones`, phone), "Teléfono agregado.");
    setPhone({ ...phone, number: "" });
  }

  return (
    <div className="page-stack">
      <PageHeader
        actions={<Button icon={Plus} onClick={openCreate}>Registrar médico</Button>}
        description="Directorio profesional conectado exclusivamente al modelo objeto-relacional de PostgreSQL."
        eyebrow="PERSONAL MÉDICO"
        title="Directorio clínico"
      />
      {error ? <div className="inline-alert inline-alert--error" role="alert">{error}<button onClick={() => setError("")} aria-label="Cerrar error"><X size={16} /></button></div> : null}
      {notice ? <div className="inline-alert inline-alert--success" role="status">{notice}<button onClick={() => setNotice("")} aria-label="Cerrar mensaje"><X size={16} /></button></div> : null}
      <div className="workspace-grid">
        <section className="section-card directory-panel" aria-labelledby="staff-list-title">
          <div className="section-card__header"><div><h2 id="staff-list-title">Médicos</h2><p>{doctors.length} profesionales registrados</p></div></div>
          <label className="module-search"><Search size={17} aria-hidden="true" /><span className="sr-only">Buscar médicos</span><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Buscar por nombre, licencia o especialidad" /></label>
          {loading ? <LoadingState label="Cargando personal" /> : error && !doctors.length ? <ErrorState message={error} onRetry={() => void load()} /> : filtered.length ? (
            <div className="record-list">
              {filtered.map((doctor) => (
                <button className={`record-row ${selected?.id === doctor.id ? "is-selected" : ""}`} key={doctor.id} onClick={() => void openDetail(doctor.id)}>
                  <span className="avatar"><UserRound size={18} /></span>
                  <span className="record-row__main"><strong>{doctor.first_name} {doctor.last_name}</strong><small>{doctor.license}</small></span>
                  <Badge tone="info">{doctor.specialty}</Badge>
                </button>
              ))}
            </div>
          ) : <EmptyState title="Sin médicos" description="No hay profesionales que coincidan con la búsqueda." icon={Stethoscope} />}
        </section>

        <section className="section-card detail-panel" aria-labelledby="staff-detail-title">
          {selected ? <>
            <div className="detail-heading">
              <div><p className="page-header__eyebrow">PERFIL PROFESIONAL</p><h2 id="staff-detail-title">{selected.first_name} {selected.last_name}</h2><p>{selected.specialty} · {selected.license}</p></div>
              <div className="detail-actions"><Button variant="secondary" onClick={openEdit}>Editar</Button><Button className="button--danger" icon={Trash2} variant="ghost" onClick={() => void removeDoctor()}>Eliminar</Button></div>
            </div>
            <dl className="detail-grid">
              <div><dt><Mail size={14} /> Correo</dt><dd>{selected.email}</dd></div>
              <div><dt><Building2 size={14} /> Clínica</dt><dd>{selectedClinic?.name ?? "Sin clínica asignada"}</dd></div>
              <div><dt>Fecha de ingreso</dt><dd>{selected.hire_date || "No indicada"}</dd></div>
              <div><dt>Salario</dt><dd>{selected.salary == null ? "No indicado" : new Intl.NumberFormat("es-CR", { style: "currency", currency: "USD" }).format(selected.salary)}</dd></div>
            </dl>
            {selectedClinic ? <div className="subsection"><h3><MapPin size={16} /> Clínica y equipos</h3><p className="muted-copy">{[selectedClinic.address?.street, selectedClinic.address?.city, selectedClinic.address?.country].filter(Boolean).join(", ") || "Dirección no registrada"}</p><div className="chip-list">{selectedClinic.equipments?.length ? selectedClinic.equipments.map((item) => <span className="info-chip" key={item.serial_number}><Wrench size={13} /> {item.brand} {item.model} · {item.status}</span>) : <span className="muted-copy">Sin equipos registrados.</span>}</div></div> : null}
            <div className="subsection"><h3><Stethoscope size={16} /> Especialidades</h3><div className="editable-list">{(selected.specialties ?? []).map((item) => <span className="info-chip" key={item}>{item}<button aria-label={`Eliminar especialidad ${item}`} disabled={saving} onClick={() => void mutateDetail(api.delete(`/api/mor/doctors/${selected.id}/specialties/${encodeURIComponent(item)}`), "Especialidad eliminada.")}><X size={13} /></button></span>)}</div><form className="inline-form" onSubmit={(event) => void addSpecialty(event)}><label><span className="sr-only">Nueva especialidad</span><input required value={specialty} onChange={(event) => setSpecialty(event.target.value)} placeholder="Nueva especialidad" /></label><Button isLoading={saving} variant="secondary" type="submit">Agregar</Button></form></div>
            <div className="subsection"><h3><PhoneIcon size={16} /> Teléfonos</h3><div className="editable-list">{(selected.phone_numbers ?? []).map((item, index) => <span className="info-chip" key={`${item.country_code}-${item.number}-${index}`}>{item.kind}: {item.country_code} {item.number}<button aria-label={`Eliminar teléfono ${item.number}`} disabled={saving} onClick={() => void mutateDetail(api.delete(`/api/mor/doctors/${selected.id}/phones?countryCode=${encodeURIComponent(item.country_code ?? "")}&number=${encodeURIComponent(item.number ?? "")}`), "Teléfono eliminado.")}><X size={13} /></button></span>)}</div><form className="inline-form inline-form--phone" onSubmit={(event) => void addPhone(event)}><label><span className="sr-only">Código de país</span><input required value={phone.country_code} onChange={(event) => setPhone({ ...phone, country_code: event.target.value })} placeholder="+506" /></label><label><span className="sr-only">Número</span><input required value={phone.number} onChange={(event) => setPhone({ ...phone, number: event.target.value })} placeholder="Número" /></label><label><span className="sr-only">Tipo</span><select value={phone.kind} onChange={(event) => setPhone({ ...phone, kind: event.target.value })}><option>Móvil</option><option>Trabajo</option><option>Casa</option></select></label><Button isLoading={saving} variant="secondary" type="submit">Agregar</Button></form></div>
          </> : <EmptyState title="Selecciona un médico" description="Consulta su perfil, especialidades, teléfonos, clínica y equipos asociados." icon={UserRound} />}
        </section>
      </div>

      {mode ? <div className="modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setMode(null); }}><section className="modal" role="dialog" aria-modal="true" aria-labelledby="doctor-form-title"><div className="modal__header"><div><p className="page-header__eyebrow">DATOS PROFESIONALES</p><h2 id="doctor-form-title">{mode === "create" ? "Registrar médico" : "Editar médico"}</h2></div><button className="icon-button" onClick={() => setMode(null)} aria-label="Cerrar"><X /></button></div><form className="entity-form" onSubmit={(event) => void saveDoctor(event)}><div className="form-grid"><label>Nombre<input required maxLength={60} value={form.first_name} onChange={(event) => setForm({ ...form, first_name: event.target.value })} /></label><label>Apellidos<input required maxLength={60} value={form.last_name} onChange={(event) => setForm({ ...form, last_name: event.target.value })} /></label><label className="form-span">Correo electrónico<input required type="email" maxLength={120} value={form.email} onChange={(event) => setForm({ ...form, email: event.target.value })} /></label><label>Especialidad principal<input required maxLength={80} value={form.specialty} onChange={(event) => setForm({ ...form, specialty: event.target.value })} /></label><label>Licencia profesional<input required maxLength={40} value={form.license} onChange={(event) => setForm({ ...form, license: event.target.value })} /></label><label>Fecha de ingreso<input type="date" value={form.hire_date} onChange={(event) => setForm({ ...form, hire_date: event.target.value })} /></label><label>Salario (USD)<input min="0" step="0.01" type="number" value={form.salary} onChange={(event) => setForm({ ...form, salary: event.target.value })} /></label><label className="form-span">Clínica<select value={form.clinic_id} onChange={(event) => setForm({ ...form, clinic_id: event.target.value })}><option value="">Sin clínica asignada</option>{clinics.map((clinic) => <option value={clinic.id} key={clinic.id}>{clinic.name}</option>)}</select></label></div><div className="modal__footer"><Button variant="secondary" onClick={() => setMode(null)}>Cancelar</Button><Button isLoading={saving} type="submit">{mode === "create" ? "Registrar" : "Guardar cambios"}</Button></div></form></section></div> : null}
    </div>
  );
}

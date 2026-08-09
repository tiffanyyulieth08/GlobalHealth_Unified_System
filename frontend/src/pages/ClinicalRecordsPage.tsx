import { useEffect, useMemo, useState, type FormEvent } from "react";
import {
  Braces, CheckCircle2, ChevronDown, FileCode2, FilePlus2, FileSearch,
  Search, ShieldCheck, Trash2, X, XCircle,
} from "lucide-react";
import { Badge } from "../components/ui/Badge";
import { Button } from "../components/ui/Button";
import { EmptyState, ErrorState, LoadingState } from "../components/ui/States";
import { PageHeader } from "../components/ui/PageHeader";
import { ApiError, api } from "../lib/api";

type ClinicalRecord = { record_id: number; schema_name: string; clinical_document: string; created_at: string; updated_at: string };
type Schema = { schema_name: string; schema_version: string; namespace_uri: string; xsd_document: string };
type RelationalRecord = Record<string, unknown> & { record_id: number };
type XmlFailure = { kind: "malformed" | "xsd" | "other"; message: string };

const starterXml = `<?xml version="1.0" encoding="UTF-8"?>
<clinicalRecord>

</clinicalRecord>`;

function getMessage(error: unknown) {
  return error instanceof Error ? error.message : "No se pudo completar la operación.";
}

function classifyXmlError(error: unknown): XmlFailure {
  const message = getMessage(error);
  const normalized = message.toLocaleLowerCase();
  if (normalized.includes("does not conform") || normalized.includes("xsd") || normalized.includes("schema")) return { kind: "xsd", message };
  if (normalized.includes("invalid xml") || normalized.includes("parsing") || normalized.includes("malformed")) return { kind: "malformed", message };
  return { kind: "other", message };
}

function prettyDate(value: string) {
  return new Intl.DateTimeFormat("es-CR", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
}

export function ClinicalRecordsPage() {
  const [records, setRecords] = useState<ClinicalRecord[]>([]);
  const [schemas, setSchemas] = useState<Schema[]>([]);
  const [relational, setRelational] = useState<RelationalRecord[]>([]);
  const [selected, setSelected] = useState<ClinicalRecord | null>(null);
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [xmlFailure, setXmlFailure] = useState<XmlFailure | null>(null);
  const [notice, setNotice] = useState("");
  const [editorOpen, setEditorOpen] = useState(false);
  const [schemaName, setSchemaName] = useState("clinical-record-v1");
  const [xml, setXml] = useState(starterXml);
  const [editing, setEditing] = useState(false);
  const [xpath, setXpath] = useState("");
  const [nodeValue, setNodeValue] = useState("");
  const [namespaces, setNamespaces] = useState("{}");
  const [nodes, setNodes] = useState<string[]>([]);

  async function load() {
    setLoading(true);
    setError("");
    try {
      const [recordData, schemaData, relationalData] = await Promise.all([
        api.get<ClinicalRecord[]>("/api/xml/records"),
        api.get<Schema[]>("/api/xml/schemas"),
        api.get<RelationalRecord[]>("/api/xml/records/relational"),
      ]);
      setRecords(recordData);
      setSchemas(schemaData);
      setRelational(relationalData);
      if (schemaData.length && !schemaData.some((schema) => schema.schema_name === schemaName)) setSchemaName(schemaData[0].schema_name);
    } catch (requestError) { setError(getMessage(requestError)); }
    finally { setLoading(false); }
  }

  useEffect(() => { void load(); }, []);

  const filtered = useMemo(() => {
    const value = query.trim().toLocaleLowerCase();
    if (!value) return records;
    return records.filter((record) => `${record.record_id} ${record.schema_name} ${record.clinical_document}`.toLocaleLowerCase().includes(value));
  }, [query, records]);

  const schema = schemas.find((item) => item.schema_name === selected?.schema_name);
  const extracted = relational.find((item) => item.record_id === selected?.record_id);

  async function openDetail(id: number) {
    setError("");
    setNodes([]);
    try { setSelected(await api.get<ClinicalRecord>(`/api/xml/records/${id}`)); }
    catch (requestError) { setError(getMessage(requestError)); }
  }

  function openCreate() {
    setEditing(false);
    setXml(starterXml);
    setSchemaName(schemas[0]?.schema_name ?? "clinical-record-v1");
    setXmlFailure(null);
    setEditorOpen(true);
  }

  function openEdit() {
    if (!selected) return;
    setEditing(true);
    setXml(selected.clinical_document);
    setSchemaName(selected.schema_name);
    setXmlFailure(null);
    setEditorOpen(true);
  }

  async function saveRecord(event: FormEvent) {
    event.preventDefault();
    setSaving(true);
    setXmlFailure(null);
    setError("");
    try {
      const payload = { schema_name: schemaName, clinical_document: xml };
      const saved = editing && selected
        ? await api.put<ClinicalRecord>(`/api/xml/records/${selected.record_id}`, payload)
        : await api.post<ClinicalRecord>("/api/xml/records", payload);
      setSelected(saved);
      setEditorOpen(false);
      setNotice(editing ? "Expediente actualizado y validado por PostgreSQL." : "Expediente creado y validado por PostgreSQL.");
      await load();
    } catch (requestError) {
      if (requestError instanceof ApiError && requestError.status === 422) setXmlFailure(classifyXmlError(requestError));
      else setError(getMessage(requestError));
    } finally { setSaving(false); }
  }

  async function removeRecord() {
    if (!selected || !window.confirm(`¿Eliminar el expediente #${selected.record_id}? Esta acción no se puede deshacer.`)) return;
    try {
      await api.delete<void>(`/api/xml/records/${selected.record_id}`);
      setSelected(null);
      setNotice("Expediente eliminado.");
      await load();
    } catch (requestError) { setError(getMessage(requestError)); }
  }

  function parseNamespaces() {
    try {
      const parsed: unknown = JSON.parse(namespaces || "{}");
      if (!parsed || Array.isArray(parsed) || typeof parsed !== "object") throw new Error();
      return parsed as Record<string, string>;
    } catch { throw new Error("Los namespaces deben ser un objeto JSON, por ejemplo: {\"gh\":\"urn:globalhealth\"}."); }
  }

  async function replaceNode(event: FormEvent) {
    event.preventDefault();
    if (!selected) return;
    setSaving(true);
    setXmlFailure(null);
    try {
      const updated = await api.patch<ClinicalRecord>(`/api/xml/records/${selected.record_id}/content`, { xpath, value: nodeValue, namespaces: parseNamespaces() });
      setSelected(updated);
      setNotice("Contenido interno reemplazado y revalidado por el backend.");
      await load();
    } catch (requestError) {
      if (requestError instanceof ApiError && requestError.status === 422) setXmlFailure(classifyXmlError(requestError));
      else setError(getMessage(requestError));
    } finally { setSaving(false); }
  }

  async function removeNodes() {
    if (!selected || !window.confirm(`Se eliminarán los nodos que coincidan con “${xpath}”. ¿Continuar?`)) return;
    setSaving(true);
    setXmlFailure(null);
    try {
      const updated = await api.delete<ClinicalRecord>(`/api/xml/records/${selected.record_id}/content`, undefined, { xpath, namespaces: parseNamespaces() });
      setSelected(updated);
      setNotice("Nodos eliminados mediante la operación segura del backend.");
      await load();
    } catch (requestError) {
      if (requestError instanceof ApiError && requestError.status === 422) setXmlFailure(classifyXmlError(requestError));
      else setError(getMessage(requestError));
    } finally { setSaving(false); }
  }

  async function extractNodes() {
    if (!selected || !xpath.trim()) return;
    setSaving(true);
    try {
      const namespaceValue = JSON.stringify(parseNamespaces());
      const result = await api.get<{ record_id: number; nodes: string[] }>(`/api/xml/records/${selected.record_id}/nodes?xpath=${encodeURIComponent(xpath)}&namespaces=${encodeURIComponent(namespaceValue)}`);
      setNodes(result.nodes);
    } catch (requestError) { setError(getMessage(requestError)); }
    finally { setSaving(false); }
  }

  return (
    <div className="page-stack">
      <PageHeader actions={<Button icon={FilePlus2} onClick={openCreate}>Nuevo expediente</Button>} description="Documentos clínicos XML cuya validez final es determinada por PostgreSQL contra el XSD registrado." eyebrow="EXPEDIENTES XML / XSD" title="Expedientes clínicos" />
      {error ? <div className="inline-alert inline-alert--error" role="alert">{error}<button onClick={() => setError("")} aria-label="Cerrar error"><X size={16} /></button></div> : null}
      {notice ? <div className="inline-alert inline-alert--success" role="status"><CheckCircle2 size={17} />{notice}<button onClick={() => setNotice("")} aria-label="Cerrar mensaje"><X size={16} /></button></div> : null}
      {xmlFailure && !editorOpen ? <XmlValidationAlert failure={xmlFailure} onClose={() => setXmlFailure(null)} /> : null}
      <div className="workspace-grid workspace-grid--records">
        <section className="section-card directory-panel" aria-labelledby="records-list-title">
          <div className="section-card__header"><div><h2 id="records-list-title">Expedientes</h2><p>{records.length} documentos almacenados</p></div></div>
          <label className="module-search"><Search size={17} /><span className="sr-only">Buscar expedientes</span><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Buscar por ID, XSD o contenido" /></label>
          {loading ? <LoadingState label="Cargando expedientes" /> : error && !records.length ? <ErrorState message={error} onRetry={() => void load()} /> : filtered.length ? <div className="record-list">{filtered.map((record) => <button className={`record-row ${selected?.record_id === record.record_id ? "is-selected" : ""}`} key={record.record_id} onClick={() => void openDetail(record.record_id)}><span className="avatar"><FileCode2 size={18} /></span><span className="record-row__main"><strong>Expediente #{record.record_id}</strong><small>{prettyDate(record.updated_at)}</small></span><Badge tone="success">XML válido</Badge></button>)}</div> : <EmptyState icon={FileSearch} title="Sin expedientes" description="No hay documentos que coincidan con la búsqueda." />}
        </section>
        <section className="section-card detail-panel" aria-labelledby="record-detail-title">
          {selected ? <>
            <div className="detail-heading"><div><p className="page-header__eyebrow">DOCUMENTO VALIDADO</p><h2 id="record-detail-title">Expediente #{selected.record_id}</h2><p>Actualizado {prettyDate(selected.updated_at)}</p></div><div className="detail-actions"><Button variant="secondary" onClick={openEdit}>Editar XML</Button><Button className="button--danger" icon={Trash2} variant="ghost" onClick={() => void removeRecord()}>Eliminar</Button></div></div>
            <div className="validation-banner"><CheckCircle2 size={20} /><div><strong>XML válido y conforme al XSD</strong><p>Estado confirmado por el backend y PostgreSQL al persistir el documento.</p></div></div>
            <pre className="xml-view" tabIndex={0}><code>{selected.clinical_document}</code></pre>
            <details className="technical-section"><summary><span><Braces size={17} /> Sección técnica</span><ChevronDown size={17} /></summary><div className="technical-section__body"><dl className="detail-grid"><div><dt>XSD aplicado</dt><dd>{selected.schema_name}</dd></div><div><dt>Versión</dt><dd>{schema?.schema_version ?? "No informada"}</dd></div><div className="form-span"><dt>Namespace</dt><dd>{schema?.namespace_uri ?? "No informado"}</dd></div></dl><h3>Datos extraídos mediante XMLTABLE</h3>{extracted ? <div className="technical-data">{Object.entries(extracted).map(([key, value]) => <div key={key}><span>{key}</span><strong>{value == null ? "—" : String(value)}</strong></div>)}</div> : <p className="muted-copy">La API no proporcionó datos relacionales para este expediente.</p>}</div></details>
            <div className="subsection node-operations"><h3>Operaciones internas seguras</h3><p className="muted-copy">El XPath y los namespaces se procesan en PostgreSQL. Cada cambio vuelve a pasar por la validación del backend.</p><form className="entity-form" onSubmit={(event) => void replaceNode(event)}><label>Expresión XPath<input required value={xpath} onChange={(event) => setXpath(event.target.value)} placeholder="/gh:clinicalRecord/gh:diagnosis" /></label><label>Namespaces (JSON)<input value={namespaces} onChange={(event) => setNamespaces(event.target.value)} placeholder={'{"gh":"urn:globalhealth"}'} /></label><label>Nuevo contenido<input value={nodeValue} onChange={(event) => setNodeValue(event.target.value)} placeholder="Texto que reemplazará el contenido del nodo" /></label><div className="operation-actions"><Button isLoading={saving} type="submit">Reemplazar contenido</Button><Button isLoading={saving} variant="secondary" type="button" onClick={() => void extractNodes()}>Consultar XPath</Button><Button className="button--danger" icon={Trash2} variant="ghost" type="button" disabled={!xpath.trim() || saving} onClick={() => void removeNodes()}>Eliminar nodos</Button></div></form>{nodes.length ? <div className="node-results"><strong>{nodes.length} resultado(s) XPath</strong>{nodes.map((node, index) => <pre key={`${node}-${index}`}>{node}</pre>)}</div> : null}</div>
          </> : <EmptyState icon={ShieldCheck} title="Selecciona un expediente" description="Consulta el XML, el XSD aplicado y los datos extraídos por PostgreSQL." />}
        </section>
      </div>
      {editorOpen ? <div className="modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) setEditorOpen(false); }}><section className="modal modal--wide" role="dialog" aria-modal="true" aria-labelledby="xml-editor-title"><div className="modal__header"><div><p className="page-header__eyebrow">EDITOR XML</p><h2 id="xml-editor-title">{editing ? `Editar expediente #${selected?.record_id}` : "Crear expediente"}</h2></div><button className="icon-button" onClick={() => setEditorOpen(false)} aria-label="Cerrar"><X /></button></div>{xmlFailure ? <XmlValidationAlert failure={xmlFailure} onClose={() => setXmlFailure(null)} /> : null}<form className="entity-form" onSubmit={(event) => void saveRecord(event)}><label>Esquema XSD<select required value={schemaName} onChange={(event) => setSchemaName(event.target.value)}>{schemas.map((item) => <option key={item.schema_name} value={item.schema_name}>{item.schema_name} · v{item.schema_version}</option>)}</select></label><label>Documento XML<textarea className="xml-editor" required spellCheck={false} value={xml} onChange={(event) => setXml(event.target.value)} aria-describedby="xml-editor-help" /></label><p className="form-help" id="xml-editor-help">El navegador solo comprueba que el campo no esté vacío. El backend/PostgreSQL determina si el XML está bien formado y cumple el XSD.</p><div className="modal__footer"><Button variant="secondary" onClick={() => setEditorOpen(false)}>Cancelar</Button><Button isLoading={saving} type="submit">Validar y guardar</Button></div></form></section></div> : null}
    </div>
  );
}

function XmlValidationAlert({ failure, onClose }: { failure: XmlFailure; onClose: () => void }) {
  const title = failure.kind === "malformed" ? "XML malformado" : failure.kind === "xsd" ? "XML no conforme al XSD" : "El backend rechazó el documento";
  return <div className="validation-error" role="alert"><XCircle size={22} /><div><strong>{title}</strong><p>{failure.message}</p><small>Decisión recibida del backend/PostgreSQL.</small></div><button onClick={onClose} aria-label="Cerrar validación"><X size={16} /></button></div>;
}

import { ArrowLeft, MapPinOff } from "lucide-react";
import { useNavigate } from "react-router";
import { Button } from "../components/ui/Button";

export function NotFoundPage() {
  const navigate = useNavigate();

  return (
    <div className="not-found">
      <span className="not-found__icon"><MapPinOff aria-hidden="true" size={30} /></span>
      <p className="page-header__eyebrow">ERROR 404</p>
      <h1>Esta página no está disponible</h1>
      <p>La dirección puede haber cambiado o no pertenecer al espacio de trabajo.</p>
      <Button icon={ArrowLeft} onClick={() => navigate("/")}>Volver al inicio</Button>
    </div>
  );
}

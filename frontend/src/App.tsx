import { Navigate, Route, Routes } from "react-router";
import { AppLayout } from "./components/layout/AppLayout";
import { ClinicalRecordsPage } from "./pages/ClinicalRecordsPage";
import { DashboardPage } from "./pages/DashboardPage";
import { DistributionPage } from "./pages/DistributionPage";
import { NotFoundPage } from "./pages/NotFoundPage";
import { StaffPage } from "./pages/StaffPage";
import { TelemetryPage } from "./pages/TelemetryPage";

export function App() {
  return (
    <Routes>
      <Route element={<AppLayout />}>
        <Route index element={<DashboardPage />} />
        <Route path="staff" element={<StaffPage />} />
        <Route path="clinical-records" element={<ClinicalRecordsPage />} />
        <Route path="telemetry" element={<TelemetryPage />} />
        <Route path="distribution" element={<DistributionPage />} />
        <Route path="404" element={<NotFoundPage />} />
        <Route path="*" element={<Navigate to="/404" replace />} />
      </Route>
    </Routes>
  );
}

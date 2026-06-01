import { Navigate, Outlet } from "react-router-dom";

import { useAuth } from "../context/AuthContext";

export default function ProtectedRoute() {
  const { isInitializing, token } = useAuth();
  if (isInitializing) {
    return <div className="flex min-h-screen items-center justify-center bg-zinc-100 text-sm text-zinc-600">Checking session...</div>;
  }
  return token ? <Outlet /> : <Navigate to="/login" replace />;
}

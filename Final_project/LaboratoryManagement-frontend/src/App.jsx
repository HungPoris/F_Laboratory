import React, { Suspense } from "react";
import { ToastContainer } from "react-toastify";
import "./i18n";
import { AuthProvider } from "./lib";
import DynamicRouter from "./DynamicRouter";

export default function App() {
  return (
    <AuthProvider>
      <Suspense fallback={<div />}>
        <DynamicRouter />
        <ToastContainer position="top-right" />
      </Suspense>
    </AuthProvider>
  );
}

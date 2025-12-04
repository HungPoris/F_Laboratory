import React, { useEffect, useState, lazy, Suspense } from "react";
import { createBrowserRouter, RouterProvider } from "react-router-dom";
import Loading from "./components/Loading";
import ProtectedRoute from "./lib/ProtectedRoute";
import componentMap from "./componentMap";
import axios from "axios";
import Placeholder from "./pages/Placeholder";

const Fallback = (
  <div className="page-centered-loading">
    <Loading />
  </div>
);

function lazyFromLoader(loader, name) {
  if (!loader)
    return lazy(() =>
      Promise.resolve({ default: () => <Placeholder name={name} /> })
    );
  return lazy(loader);
}

function makeElement(loader, screenCode, basePath, isPublic) {
  const Comp = lazyFromLoader(loader, screenCode || basePath || "unknown");
  return (
    <Suspense fallback={Fallback}>
      <ProtectedRoute
        screenCode={screenCode}
        basePath={basePath}
        isPublic={isPublic}
      >
        <Comp />
      </ProtectedRoute>
    </Suspense>
  );
}

function resolveLoaderForRow(r) {
  if (!r) return null;
  const keys = [];
  if (r.component_name) keys.push(r.component_name);
  if (r.screen_code) keys.push(r.screen_code);
  if (r.title) keys.push(r.title);
  for (const k of keys) {
    if (!k) continue;
    if (componentMap[k]) return componentMap[k];
    const cap = k.charAt(0).toUpperCase() + k.slice(1);
    if (componentMap[cap]) return componentMap[cap];
  }
  return null;
}

export default function RouterLoader() {
  const [router, setRouter] = useState(null);
  const API = import.meta.env.VITE_API_URL || "";

  useEffect(() => {
    let mounted = true;
    (async () => {
      try {
        const res = await axios.get((API || "") + "/api/v1/screens/all");
        const rows = Array.isArray(res.data) ? res.data : [];
        if (!mounted) return;
        const routes = [];
        const rootRoute = {
          path: "/",
          element: makeElement(
            resolveLoaderForRow(rows.find((r) => r.path === "/")),
            "SCR_LANDING",
            "/",
            true
          ),
        };
        routes.push(rootRoute);
        for (const r of rows) {
          if (r.path === "/") continue;
          const loader = resolveLoaderForRow(r);
          routes.push({
            path: r.path,
            element: makeElement(
              loader,
              r.screen_code,
              r.base_path || r.path,
              !!r.is_public
            ),
          });
        }
        routes.push({
          path: "*",
          element: (
            <Suspense fallback={Fallback}>
              <Placeholder name="NotFound" />
            </Suspense>
          ),
        });
        const created = createBrowserRouter(routes);
        setRouter(created);
      // eslint-disable-next-line no-unused-vars
      } catch (e) {
        const created = createBrowserRouter([
          {
            path: "/",
            element: (
              <Suspense fallback={Fallback}>
                <Placeholder name="fallback" />
              </Suspense>
            ),
          },
          {
            path: "*",
            element: (
              <Suspense fallback={Fallback}>
                <Placeholder name="NotFound" />
              </Suspense>
            ),
          },
        ]);
        setRouter(created);
      }
    })();
    return () => {
      mounted = false;
    };
  }, [API]);

  if (!router)
    return (
      <div className="page-centered-loading">
        <Loading />
      </div>
    );
  return <RouterProvider router={router} />;
}

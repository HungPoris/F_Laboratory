import React, { useEffect, useState, Suspense, lazy } from "react";
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import axios from "axios";
import componentMap from "./componentMap";
import ProtectedRoute from "./lib/ProtectedRoute";
import Placeholder from "./pages/Placeholder.jsx";
import Login from "./pages/Login.jsx";
import ForgotSend from "./pages/ForgotSend.jsx";
import ForgotVerify from "./pages/ForgotVerify.jsx";
import ForgotReset from "./pages/ForgotReset.jsx";
import Loading from "./components/Loading.jsx";
import Forbidden403 from "./pages/Forbidden403.jsx";
import NotFound from "./pages/NotFound.jsx";
import { useAuth } from "./lib";

function LazyComp(loader, name) {
  if (!loader) {
    return lazy(() =>
      // eslint-disable-next-line no-unused-vars
      Promise.resolve({ default: (props) => <Placeholder name={name} /> })
    );
  }
  return lazy(() =>
    loader().catch(() =>
      import("./pages/Placeholder.jsx").then(() => ({
        default: (props) => <Placeholder name={name} {...props} />,
      }))
    )
  );
}

function toPascal(s) {
  if (!s) return s;
  return String(s)
    .replace(/[^A-Za-z0-9]+/g, " ")
    .split(/\s+/)
    .filter(Boolean)
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase())
    .join("");
}

function resolveLoader(item) {
  if (!item) return null;
  if (item.screen_code) {
    const sc = String(item.screen_code);
    if (componentMap[sc]) return componentMap[sc];
  }
  const tryKeys = [];
  if (item.component_name) tryKeys.push(item.component_name);
  if (item.screen_code) tryKeys.push(item.screen_code);
  if (item.title) tryKeys.push(item.title);
  const cleanedCode = item.screen_code
    ? String(item.screen_code).replace(/[^A-Za-z0-9_]/g, "")
    : null;
  if (cleanedCode) tryKeys.push(cleanedCode);
  if (item.screen_code) tryKeys.push(toPascal(item.screen_code));
  if (item.component_name) tryKeys.push(toPascal(item.component_name));
  if (item.screen_code) {
    const sc = String(item.screen_code);
    if (sc === "ADMIN_ROLES_LIST" || sc === "SCR_ADMIN_ROLES") {
      tryKeys.push("RolesList", "Roles", "AdminRolesList", "AdminRoles");
    }
    if (
      sc === "ADMIN_PRIVILEGES_LIST" ||
      sc === "SCR_ADMIN_PRIVS" ||
      sc === "SCR_ADMIN_PRIVILEGES"
    ) {
      tryKeys.push(
        "PrivilegesList",
        "Privileges",
        "AdminPrivilegesList",
        "AdminPrivileges"
      );
    }
    if (sc.startsWith("SCR_")) {
      const withoutPrefix = sc.replace(/^SCR_/, "");
      tryKeys.push(withoutPrefix, toPascal(withoutPrefix));
      if (withoutPrefix.includes("ADMIN_")) {
        const parts = withoutPrefix.split("_");
        if (parts.length > 1) {
          const lastPart = parts[parts.length - 1];
          if (lastPart === "ROLES" || lastPart === "Roles") {
            tryKeys.push("RolesList", "Roles");
          } else if (
            lastPart === "PRIVS" ||
            lastPart === "Privs" ||
            lastPart === "PRIVILEGES" ||
            lastPart === "Privileges"
          ) {
            tryKeys.push("PrivilegesList", "Privileges");
          } else {
            tryKeys.push(lastPart + "List", toPascal(lastPart) + "List");
          }
        }
      }
    }
  }
  if (item.component_name) {
    const cn = String(item.component_name);
    if (!cn.endsWith("List") && !cn.endsWith("LIST")) {
      tryKeys.push(cn + "List", cn + "LIST");
    }
    if (cn.endsWith("List")) {
      tryKeys.push(cn.replace(/List$/, ""));
    }
    if (cn.endsWith("LIST")) {
      tryKeys.push(cn.replace(/LIST$/, ""));
    }
  }
  for (const k of tryKeys) {
    if (!k) continue;
    if (componentMap[k]) return componentMap[k];
    const cap = k.charAt(0).toUpperCase() + k.slice(1);
    if (componentMap[cap]) return componentMap[cap];
    const up = k.toUpperCase();
    if (componentMap[up]) return componentMap[up];
  }
  return null;
}

export default function DynamicRouter() {
  const [routesData, setRoutesData] = useState([]);
  const [routesLoading, setRoutesLoading] = useState(true);
  const { token, loading, initialized } = useAuth() || {};
  const API =
    import.meta.env.VITE_API_BASE_URL || import.meta.env.VITE_API_URL || "";

  useEffect(() => {
    let mounted = true;
    async function fetchScreens() {
      if (!initialized) return;

      setRoutesLoading(true);
      try {
        const url = (API || "") + "/api/v1/screens/all";
        const headers = token ? { Authorization: `Bearer ${token}` } : {};
        const res = await axios.get(url, { headers });
        const data = Array.isArray(res?.data) ? res.data : [];
        if (!mounted) return;
        const mapped = data.map((r) => {
          const loader = resolveLoader(r);
          return {
            screen_code: r.screen_code,
            path: r.path,
            base_path: r.base_path || r.basePath || r.path,
            component_name: r.component_name,
            title: r.title,
            is_public: !!r.is_public,
            is_menu: !!r.is_menu,
            ordering: r.ordering || 0,
            parent_code: r.parent_code || r.parentCode || null,
            loader,
          };
        });
        setRoutesData(mapped);
      } catch {
        setRoutesData([]);
      } finally {
        if (mounted) setRoutesLoading(false);
      }
    }

    if (!loading && initialized) {
      fetchScreens();
    }

    return () => {
      mounted = false;
    };
  }, [API, token, loading, initialized]);

  if (loading || !initialized || routesLoading) {
    return <Loading size={60} />;
  }

  return (
    <BrowserRouter>
      <Suspense fallback={<Loading size={40} />}>
        <Routes>
          <Route path="/" element={<Login />} />
          <Route path="/login" element={<Login />} />
          <Route path="/forgot-password" element={<ForgotSend />} />
          <Route path="/forgot-password/verify" element={<ForgotVerify />} />
          <Route path="/forgot-password/reset" element={<ForgotReset />} />
          <Route
            path="/forgot-password/:correlationId"
            element={<ForgotVerify />}
          />
          <Route path="/verify-otp" element={<ForgotVerify />} />
          <Route path="/verify-otp/:correlationId" element={<ForgotVerify />} />
          <Route path="/reset-password" element={<ForgotReset />} />
          <Route path="/reset-password/:token" element={<ForgotReset />} />

          {/* Static Test Order Routes */}
          {/* Static Medical Record Routes */}
          <Route
            path="/patients/:patientId/medical-records/new"
            element={(() => {
              const Comp = LazyComp(
                componentMap.MedicalRecordCreate,
                "MedicalRecordCreate"
              );
              return (
                <ProtectedRoute basePath="/patients/:patientId/medical-records/new">
                  <Comp />
                </ProtectedRoute>
              );
            })()}
          />

          <Route
            path="/patients/:patientId/medical-records/:recordId"
            element={(() => {
              const Comp = LazyComp(
                componentMap.MedicalRecordView,
                "MedicalRecordView"
              );
              return (
                <ProtectedRoute basePath="/patients/:patientId/medical-records/:recordId">
                  <Comp />
                </ProtectedRoute>
              );
            })()}
          />

          <Route
            path="/patients/:patientId/medical-records/:recordId/edit"
            element={(() => {
              const Comp = LazyComp(
                componentMap.MedicalRecordEdit,
                "MedicalRecordEdit"
              );
              return (
                <ProtectedRoute basePath="/patients/:patientId/medical-records/:recordId/edit">
                  <Comp />
                </ProtectedRoute>
              );
            })()}
          />

          <Route
            path="/test-orders"
            element={(() => {
              const Comp = LazyComp(
                componentMap.TestOrderList,
                "TestOrderList"
              );
              return (
                <ProtectedRoute basePath="/test-orders">
                  <Comp />
                </ProtectedRoute>
              );
            })()}
          />
          <Route
            path="/test-orders/new"
            element={(() => {
              const Comp = LazyComp(
                componentMap.TestOrderCreate,
                "TestOrderCreate"
              );
              return (
                <ProtectedRoute basePath="/test-orders/new">
                  <Comp />
                </ProtectedRoute>
              );
            })()}
          />
          <Route
            path="/test-orders/:id"
            element={(() => {
              const Comp = LazyComp(
                componentMap.TestOrderDetail,
                "TestOrderDetail"
              );
              return (
                <ProtectedRoute basePath="/test-orders/:id">
                  <Comp />
                </ProtectedRoute>
              );
            })()}
          />
          <Route
            path="/test-orders/:id/edit"
            element={(() => {
              const Comp = LazyComp(
                componentMap.TestOrderEdit,
                "TestOrderEdit"
              );
              return (
                <ProtectedRoute basePath="/test-orders/:id/edit">
                  <Comp />
                </ProtectedRoute>
              );
            })()}
          />

          {/* Static Test Result Routes */}
          <Route
            path="/test-results"
            element={(() => {
              const Comp = LazyComp(
                componentMap.TestResultList,
                "TestResultList"
              );
              return (
                <ProtectedRoute basePath="/test-results">
                  <Comp />
                </ProtectedRoute>
              );
            })()}
          />

          {(() => {
            const isProfile = (p) =>
              typeof p === "string" && p.startsWith("/profile");
            const profileRoutes = routesData.filter((r) => isProfile(r.path));
            const otherRoutes = routesData.filter((r) => !isProfile(r.path));

            const makeEl = (r) => {
              const Comp = r.loader
                ? LazyComp(r.loader, r.title || r.screen_code)
                : LazyComp(null, r.title || r.screen_code);
              return (
                <ProtectedRoute
                  screenCode={r.screen_code}
                  basePath={r.base_path}
                  isPublic={r.is_public}
                >
                  <Comp />
                </ProtectedRoute>
              );
            };

            const nodes = [];

            otherRoutes.forEach((r) => {
              nodes.push(
                <Route
                  key={r.screen_code || r.path}
                  path={r.path}
                  element={makeEl(r)}
                />
              );
            });

            if (profileRoutes.length > 0) {
              const LayoutComp = LazyComp(
                componentMap.ProfileLayout,
                "ProfileLayout"
              );
              const profileChildren = profileRoutes.filter(
                (c) =>
                  (c.screen_code || "") !== "PROFILE_ROOT" &&
                  (c.component_name || "") !== "ProfileLayout" &&
                  (c.component_key || "") !== "ProfileLayout"
              );

              nodes.push(
                <Route
                  key="profile$layout"
                  path="/profile/*"
                  element={<LayoutComp />}
                >
                  {profileChildren.map((c) => {
                    const p = "/profile";
                    const cp = c.path;
                    if (cp === p)
                      return (
                        <Route
                          index
                          key={c.screen_code || c.path}
                          element={makeEl(c)}
                        />
                      );
                    const rel = cp.startsWith(p + "/")
                      ? cp.slice(p.length + 1)
                      : cp;
                    return (
                      <Route
                        key={c.screen_code || c.path}
                        path={rel}
                        element={makeEl(c)}
                      />
                    );
                  })}
                </Route>
              );
            }

            return nodes;
          })()}

          <Route
            path="/profile/security"
            element={
              <Navigate to="/profile/security/change-password" replace />
            }
          />
          <Route path="/403" element={<Forbidden403 />} />
          <Route path="/404" element={<NotFound />} />
          <Route path="*" element={<NotFound />} />
        </Routes>
      </Suspense>
    </BrowserRouter>
  );
}

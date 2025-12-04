import React, { useEffect, useState } from "react";
import { Navigate, useLocation, useNavigate } from "react-router-dom";
import { useAuth } from "./index";
import { getLoginPath } from "./loginRedirect";
import RoleAwareLayout from "../layouts/RoleAwareLayout";

const PUBLIC_PATHS = [
  "/",
  "/login",
  "/admin/login",
  "/forgot-password",
  "/verify-otp",
  "/404",
  "/403",
];
const PROFILE_PREFIX = "/profile";

export default function ProtectedRoute({
  children,
  screenCode,
  // eslint-disable-next-line no-unused-vars
  basePath,
  isPublic,
}) {
  const { user, loading, initialized } = useAuth() || {};
  const location = useLocation();
  const navigate = useNavigate();
  const [accessChecked, setAccessChecked] = useState(false);

  useEffect(() => {
    setAccessChecked(false);
  }, [location.pathname]);

  useEffect(() => {
    if (!loading && initialized && !accessChecked) {
      checkAccess();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [loading, initialized, accessChecked, user, location.pathname]);

  const checkAccess = () => {
    const pathname = location.pathname || "";

    if (isPublic) {
      setAccessChecked(true);
      return;
    }

    for (const p of PUBLIC_PATHS) {
      if (pathname === p || pathname.startsWith(p + "/")) {
        setAccessChecked(true);
        return;
      }
    }
    if (!user) {
      setAccessChecked(true);
      return;
    }

    if (
      pathname.startsWith(PROFILE_PREFIX) ||
      (screenCode && String(screenCode).startsWith("PROFILE_"))
    ) {
      setAccessChecked(true);
      return;
    }

    const accessible = Array.isArray(user?.accessibleScreens)
      ? user.accessibleScreens
      : [];

    const accessibleDetailed = Array.isArray(user?.accessibleScreensDetailed)
      ? user.accessibleScreensDetailed.map((s) => s.screenCode)
      : [];

    const allAccessible = [...new Set([...accessible, ...accessibleDetailed])];

    if (screenCode) {
      if (!allAccessible.includes(screenCode)) {
        navigate("/403", { replace: true, state: { from: location } });
        setAccessChecked(true);
        return;
      }
    }

    setAccessChecked(true);
  };

  if (loading || !initialized) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="text-center">
          <div className="inline-block animate-spin rounded-full h-12 w-12 border-b-2 border-gray-900 mb-4"></div>
          <p className="text-gray-600">Loading user information...</p>
        </div>
      </div>
    );
  }

  if (!accessChecked) {
    return null;
  }

  const pathname = location.pathname || "";

  if (isPublic) {
    return <>{children}</>;
  }

  for (const p of PUBLIC_PATHS) {
    if (pathname === p || pathname.startsWith(p + "/")) {
      return <>{children}</>;
    }
  }

  if (!user) {
    const loginPath = getLoginPath();
    if (loginPath === "/login") {
      try {
        sessionStorage.setItem("lm.shouldReloadLogin", "true");
      } catch {
        /* empty */
      }
    }
    if (
      pathname.startsWith("/admin") &&
      !localStorage.getItem("lm.loginType")
    ) {
      return <Navigate to="/admin/login" state={{ from: location }} replace />;
    }
    return <Navigate to={loginPath} state={{ from: location }} replace />;
  }

  if (
    pathname.startsWith(PROFILE_PREFIX) ||
    (screenCode && String(screenCode).startsWith("PROFILE_"))
  ) {
    return <RoleAwareLayout>{children}</RoleAwareLayout>;
  }

  const accessible = Array.isArray(user?.accessibleScreens)
    ? user.accessibleScreens
    : [];

  const accessibleDetailed = Array.isArray(user?.accessibleScreensDetailed)
    ? user.accessibleScreensDetailed.map((s) => s.screenCode)
    : [];

  const allAccessible = [...new Set([...accessible, ...accessibleDetailed])];

  if (screenCode) {
    if (allAccessible.includes(screenCode)) {
      return <RoleAwareLayout>{children}</RoleAwareLayout>;
    }
    return null;
  }

  if (pathname.startsWith("/admin")) {
    return <RoleAwareLayout>{children}</RoleAwareLayout>;
  }

  return <RoleAwareLayout>{children}</RoleAwareLayout>;
}

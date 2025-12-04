export function setLoginEntryPath(pathname) {
  try {
    if (pathname && typeof pathname === "string" && pathname.startsWith("/")) {
      localStorage.setItem("lm.loginEntryPath", pathname);
    }
  } catch {
    /* ignore */
  }
}

export function getLoginRedirectPath() {
  try {
    const stored = localStorage.getItem("lm.loginEntryPath");
    if (stored && typeof stored === "string" && stored.startsWith("/")) {
      return stored;
    }
  } catch {
    /* ignore */
  }
  return "/login";
}

// Lưu loại login (user hoặc admin)
export function setLoginType(loginType) {
  try {
    if (loginType === "admin" || loginType === "user") {
      localStorage.setItem("lm.loginType", loginType);
    }
  } catch {
    /* ignore */
  }
}

export function getLoginType() {
  try {
    const stored = localStorage.getItem("lm.loginType");
    if (stored === "admin" || stored === "user") {
      return stored;
    }
  } catch {
    /* ignore */
  }
  return null;
}

export function clearLoginType() {
  try {
    localStorage.removeItem("lm.loginType");
  } catch {
    /* ignore */
  }
}

export function getLoginPath() {
  if (typeof window !== "undefined" && window.location?.pathname) {
    const currentPath = window.location.pathname;
    if (currentPath.startsWith("/admin")) {
      return "/admin/login";
    }
  }

  const loginType = getLoginType();
  if (loginType === "admin") {
    return "/admin/login";
  }

  return "/login";
}

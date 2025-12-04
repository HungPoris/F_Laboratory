// src/lib/index.jsx
import React, {
  createContext,
  useContext,
  useEffect,
  useState,
  useCallback,
  useRef,
} from "react";
import http from "./api";
import {
  getAccessToken,
  setAccessToken as setAT,
  setRefreshToken as setRT,
  clearSession,
} from "./api";
import { getLoginPath, clearLoginType } from "./loginRedirect";

const AuthContext = createContext(null);

function normalizeRoles(rs) {
  try {
    if (!rs) return [];
    if (Array.isArray(rs)) return rs.map((r) => String(r).toUpperCase());
    return [];
  } catch {
    return [];
  }
}

function normalizePrivileges(ps) {
  try {
    if (!ps) return [];
    if (Array.isArray(ps)) return ps.map((p) => String(p));
    return [];
  } catch {
    return [];
  }
}

export function AuthProvider({ children }) {
  const [token, setToken] = useState(getAccessToken());
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(Boolean(getAccessToken()));
  const [initialized, setInitialized] = useState(false);
  const idleTimerRef = useRef(null);

  const IDLE_MINUTES = Number(import.meta.env.VITE_IDLE_MINUTES || 15);
  const IDLE_MS = IDLE_MINUTES * 60 * 1000;

  const API_BASE = (import.meta.env.VITE_API_BASE_URL || "").replace(
    /\/+$/,
    ""
  );
  const ME_ENDPOINT =
    (API_BASE ? API_BASE : "") +
    (import.meta.env.VITE_ME_ENDPOINT || "/api/v1/auth/me");
  const LOGOUT_ENDPOINT =
    (API_BASE ? API_BASE : "") +
    (import.meta.env.VITE_LOGOUT_ENDPOINT || "/api/v1/auth/logout");

  const redirectToLogin = useCallback(() => {
    try {
      const loginPath = getLoginPath();
      window.location.href = loginPath;
    } catch {
      try {
        const loginPath = getLoginPath();
        window.location.replace(loginPath);
      } catch {
        /* empty */
      }
    }
  }, []);

  const resetIdle = useCallback(() => {
    if (idleTimerRef.current) {
      clearTimeout(idleTimerRef.current);
      idleTimerRef.current = null;
    }
    if (getAccessToken()) {
      idleTimerRef.current = setTimeout(() => {
        try {
          clearSession();
          delete http.defaults.headers.common.Authorization;
        } catch {
          /* empty */
        }
        setToken(null);
        setUser(null);
        redirectToLogin();
      }, IDLE_MS);
    }
  }, [IDLE_MS, redirectToLogin]);

  useEffect(() => {
    // Kiểm tra xem có đang ở trang login không
    const isLoginPage =
      typeof window !== "undefined" &&
      (window.location.pathname === "/login" ||
        window.location.pathname === "/admin/login" ||
        window.location.pathname === "/");

    // Nếu đang ở trang login, clear session và không gọi loadMe() để tránh lỗi CORS và 429
    if (isLoginPage) {
      try {
        clearSession();
        delete http.defaults.headers.common.Authorization;
        setToken(null);
        setUser(null);
      } catch {
        /* empty */
      }
      setLoading(false);
      setInitialized(true);
      return;
    }

    const storedToken = getAccessToken();
    if (storedToken) {
      setToken(storedToken);
      http.defaults.headers.common.Authorization = `Bearer ${storedToken}`;
      (async () => {
        try {
          await loadMe();
        } finally {
          setInitialized(true);
        }
      })();
    } else {
      setLoading(false);
      setInitialized(true);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    const interceptorId = http.interceptors.response.use(
      (res) => {
        try {
          resetIdle();
        } catch {
          /* empty */
        }
        return res;
      },
      (err) => {
        try {
          resetIdle();
        } catch {
          /* empty */
        }
        return Promise.reject(err);
      }
    );
    return () => http.interceptors.response.eject(interceptorId);
  }, [resetIdle]);

  // ===== Modified function: make it async and return loadMe() when appropriate =====
  async function loginWithToken(
    accessToken,
    refreshToken = null,
    userInfo = null
  ) {
    if (accessToken) {
      setAT(accessToken);
      http.defaults.headers.common.Authorization = `Bearer ${accessToken}`;
    }
    if (refreshToken) setRT(refreshToken);
    setToken(accessToken || null);

    if (userInfo) {
      const roles = normalizeRoles(
        userInfo.roles || userInfo.authorities || []
      );
      const privileges = normalizePrivileges(
        userInfo.privileges || userInfo.permissions || []
      );
      setUser({
        id: userInfo.id || userInfo.userId || null,
        username: userInfo.username || userInfo.name || null,
        fullName: userInfo.fullName || userInfo.name || null,
        roles,
        privileges,
        accessibleScreens: userInfo.accessibleScreens || [],
        raw: userInfo,
      });
      setLoading(false);
      setInitialized(true);
      // return resolved promise so callers can await that the user was set
      return Promise.resolve(userInfo);
    } else if (accessToken) {
      // If only token is provided, load user info from server and return that promise
      return loadMe();
    } else {
      setUser(null);
      setLoading(false);
      setInitialized(true);
    }
    resetIdle();
  }
  // ===== end modified function =====

  async function logout() {
    // Clear session và token NGAY LẬP TỨC trước khi gọi API logout
    // Điều này ngăn các request khác được gửi với token cũ
    const currentPath =
      typeof window !== "undefined" ? window.location.pathname : null;
    const isAdminPath = currentPath?.startsWith("/admin");

    // Clear ngay lập tức
    clearSession();
    // Xóa luôn loại login để lần đăng nhập sau không bị "kẹt" ở portal cũ
    try {
      clearLoginType();
    } catch {
      /* empty */
    }
    delete http.defaults.headers.common.Authorization;
    setToken(null);
    setUser(null);

    // Sau đó mới gọi API logout (nếu có token thì sẽ không có vì đã clear)
    try {
      await http.post(LOGOUT_ENDPOINT, null, { meta: { public: true } });
    } catch {
      /* empty */
    }

    // Redirect dựa trên pathname hiện tại
    const loginPath = isAdminPath ? "/admin/login" : "/login";
    try {
      // Set flag để Login page biết không cần reload (vì đã reload rồi)
      if (loginPath === "/login") {
        try {
          sessionStorage.setItem("lm.skipReloadLogin", "true");
        } catch {
          /* empty */
        }
      }
      // Sử dụng replace thay vì href để tránh lưu vào history
      window.location.replace(loginPath);
    } catch {
      try {
        if (loginPath === "/login") {
          try {
            sessionStorage.setItem("lm.skipReloadLogin", "true");
          } catch {
            /* empty */
          }
        }
        window.location.href = loginPath;
      } catch {
        /* empty */
      }
    }
  }

  useEffect(() => {
    const onActivity = () => resetIdle();
    const events = [
      "mousemove",
      "mousedown",
      "keydown",
      "touchstart",
      "visibilitychange",
    ];
    events.forEach((e) => window.addEventListener(e, onActivity));
    resetIdle();
    const onStorage = (e) => {
      if (e.key === "app:logout") {
        try {
          clearSession();
          delete http.defaults.headers.common.Authorization;
        } catch {
          /* empty */
        }
        setToken(null);
        setUser(null);
        const loginPath = getLoginPath();
        if (window.location.pathname !== loginPath)
          window.location.href = loginPath;
      }
    };
    window.addEventListener("storage", onStorage);
    return () => {
      events.forEach((e) => window.removeEventListener(e, onActivity));
      if (idleTimerRef.current) {
        clearTimeout(idleTimerRef.current);
        idleTimerRef.current = null;
      }
      window.removeEventListener("storage", onStorage);
    };
  }, [resetIdle]);

  const tryRefresh = useCallback(async () => {
    try {
      const REFRESH_ENDPOINT =
        ((import.meta.env.VITE_API_BASE_URL || "").replace(/\/+$/, "") || "") +
        (import.meta.env.VITE_TOKEN_REFRESH_ENDPOINT || "/api/v1/auth/refresh");
      const storedRefresh = (() => {
        try {
          return localStorage.getItem("lm.refresh");
        } catch {
          return null;
        }
      })();
      const url = REFRESH_ENDPOINT;
      const resp = storedRefresh
        ? await fetch(url, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ refreshToken: storedRefresh }),
            credentials: "include",
          })
        : await fetch(url, { method: "POST", credentials: "include" });
      if (!resp || !resp.ok) return null;
      const body = await resp.json();
      const newToken = body?.accessToken || body?.token || null;
      const newRefresh = body?.refreshToken || null;
      if (newToken) {
        try {
          localStorage.setItem("lm.access", newToken);
        } catch {
          /* empty */
        }
        setAT(newToken);
        http.defaults.headers.common.Authorization = `Bearer ${newToken}`;
      }
      if (newRefresh) {
        try {
          localStorage.setItem("lm.refresh", newRefresh);
        } catch {
          /* empty */
        }
        setRT(newRefresh);
      }
      return newToken;
    } catch {
      return null;
    }
  }, []);

  const loadMe = useCallback(async () => {
    // Kiểm tra xem có đang ở trang login không - nếu có thì không gọi API
    const isLoginPage =
      typeof window !== "undefined" &&
      (window.location.pathname === "/login" ||
        window.location.pathname === "/admin/login" ||
        window.location.pathname === "/");

    if (isLoginPage) {
      setLoading(false);
      setInitialized(true);
      return;
    }

    setLoading(true);
    try {
      const res = await http.get(ME_ENDPOINT);
      const data = res?.data || null;
      if (data) {
        const roles = normalizeRoles(
          data.roles || data.authorities || data.roles || []
        );
        const privileges = normalizePrivileges(
          data.privileges || data.permissions || data.authorities || []
        );
        let accessibleScreens = [];
        try {
          const screensRes = await http.get("/api/v1/ui/accessible-screens");
          accessibleScreens = screensRes?.data?.accessible_screens || [];
        } catch {
          accessibleScreens = [];
        }
        setUser({
          id: data.id || data.userId || null,
          username: data.username || data.name || null,
          fullName: data.fullName || data.name || data.username || null,
          roles,
          privileges,
          accessibleScreens,
          raw: data,
        });
      } else {
        setUser(null);
      }
    } catch (e) {
      const status = e?.response?.status || null;
      if (status === 401) {
        const refreshed = await tryRefresh();
        if (refreshed) {
          try {
            const r2 = await http.get(ME_ENDPOINT);
            const d2 = r2?.data || null;
            if (d2) {
              const roles = normalizeRoles(
                d2.roles || d2.authorities || d2.roles || []
              );
              const privileges = normalizePrivileges(
                d2.privileges || d2.permissions || d2.authorities || []
              );
              let accessibleScreens = [];
              try {
                const screensRes = await http.get(
                  "/api/v1/ui/accessible-screens"
                );
                accessibleScreens = screensRes?.data?.accessible_screens || [];
              } catch {
                accessibleScreens = [];
              }
              setUser({
                id: d2.id || d2.userId || null,
                username: d2.username || d2.name || null,
                fullName: d2.fullName || d2.name || d2.username || null,
                roles,
                privileges,
                accessibleScreens,
                raw: d2,
              });
              setLoading(false);
              setInitialized(true);
              resetIdle();
              return;
            }
          } catch {
            /* empty */
          }
        }
      }
      if (status === 401 || status === 403) {
        try {
          clearSession();
          delete http.defaults.headers.common.Authorization;
          setToken(null);
          setUser(null);
        } catch {
          /* empty */
        }
      }
    } finally {
      setLoading(false);
      setInitialized(true);
    }
  }, [ME_ENDPOINT, tryRefresh, resetIdle]);

  function hasRole(role) {
    if (!user || !Array.isArray(user.roles)) return false;
    return user.roles.includes(String(role).toUpperCase());
  }

  function hasAnyRole(roles) {
    if (!user || !Array.isArray(user.roles) || !Array.isArray(roles))
      return false;
    const want = roles.map((r) => String(r).toUpperCase());
    return user.roles.some((r) => want.includes(r));
  }

  function hasPrivilege(priv) {
    if (!user || !Array.isArray(user.privileges)) return false;
    return user.privileges.includes(String(priv));
  }

  return (
    <AuthContext.Provider
      value={{
        token,
        setToken,
        user,
        setUser,
        loading,
        initialized,
        loginWithToken,
        logout,
        signOut: logout,
        loadMe,
        hasRole,
        hasAnyRole,
        hasPrivilege,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

// eslint-disable-next-line react-refresh/only-export-components
export function useAuth() {
  return useContext(AuthContext);
}

export default AuthProvider;

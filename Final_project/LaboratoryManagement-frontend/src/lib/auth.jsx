import React, {
  createContext,
  useContext,
  useEffect,
  useState,
  useRef,
} from "react";
import http from "./api";
import {
  getAccessToken,
  setAccessToken as setAT,
  setRefreshToken as setRT,
  clearSession,
} from "./api";
import { isTokenExpiringSoon, getTokenRemainingTime } from "./tokenUtils";
import { getLoginPath } from "./loginRedirect";
import SessionToast from "../components/SessionToast";

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

  const [showSessionWarning, setShowSessionWarning] = useState(false);

  const warningTimerRef = useRef(null);
  const logoutTimerRef = useRef(null);

  const WARNING_THRESHOLD_MS = 1 * 60 * 1000;

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

  // eslint-disable-next-line no-unused-vars
  const redirectToLogin = () => {
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
  };

  const clearWarningTimers = () => {
    if (warningTimerRef.current) {
      clearTimeout(warningTimerRef.current);
      warningTimerRef.current = null;
    }
    if (logoutTimerRef.current) {
      clearTimeout(logoutTimerRef.current);
      logoutTimerRef.current = null;
    }
  };

  const tryRefresh = async () => {
    try {
      const REFRESH_ENDPOINT =
        ((
          import.meta.env.VITE_API_URL ||
          import.meta.env.VITE_API_BASE_URL ||
          ""
        ).replace(/\/+$/, "") || "") +
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
        setToken(newToken);
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
  };

  const logout = async () => {
    // Clear session và token NGAY LẬP TỨC trước khi gọi API logout
    // Điều này ngăn các request khác được gửi với token cũ
    const currentPath =
      typeof window !== "undefined" ? window.location.pathname : null;
    const isAdminPath = currentPath?.startsWith("/admin");

    // Clear ngay lập tức
    clearSession();
    delete http.defaults.headers.common.Authorization;
    setToken(null);
    setUser(null);
    clearWarningTimers();

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
  };

  const scheduleWarning = () => {
    clearWarningTimers();

    const currentToken = getAccessToken();
    if (!currentToken) return;

    const remainingTime = getTokenRemainingTime(currentToken);
    const warningTime = Math.max(0, remainingTime - WARNING_THRESHOLD_MS);

    if (warningTime > 0) {
      warningTimerRef.current = setTimeout(() => {
        setShowSessionWarning(true);

        logoutTimerRef.current = setTimeout(() => {
          logout();
        }, WARNING_THRESHOLD_MS);
      }, warningTime);
    } else if (remainingTime > 0) {
      setShowSessionWarning(true);

      logoutTimerRef.current = setTimeout(() => {
        logout();
      }, remainingTime);
    }
  };

  const handleWarningClose = () => {
    setShowSessionWarning(false);
  };

  const loadMe = async () => {
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
      const currentToken = getAccessToken();
      if (currentToken && isTokenExpiringSoon(currentToken, 60000)) {
        await tryRefresh();
      }

      const res = await http.get(ME_ENDPOINT);
      const data = res?.data || null;

      if (data) {
        const roles = normalizeRoles(data.roles || data.authorities || []);
        const privileges = normalizePrivileges(
          data.privileges || data.permissions || []
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

        scheduleWarning();
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
              const roles = normalizeRoles(d2.roles || d2.authorities || []);
              const privileges = normalizePrivileges(
                d2.privileges || d2.permissions || []
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
              scheduleWarning();
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
  };

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
          if (isTokenExpiringSoon(storedToken, 60000)) {
            await tryRefresh();
          }

          await loadMe();
        } catch {
          /* empty */
        } finally {
          setInitialized(true);
        }
      })();
    } else {
      setLoading(false);
      setInitialized(true);
    }
  }, []);

  const loginWithToken = (
    accessToken,
    refreshToken = null,
    userInfo = null
  ) => {
    return new Promise((resolve) => {
      if (accessToken) {
        setAT(accessToken);
        http.defaults.headers.common.Authorization = `Bearer ${accessToken}`;
      }
      if (refreshToken) setRT(refreshToken);
      setToken(accessToken || null);

      if (userInfo) {
        // Khi có userInfo, set user trực tiếp, không gọi loadMe() để tránh duplicate request
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
        if (accessToken) {
          scheduleWarning();
        }
        // Đợi một chút để đảm bảo state đã được cập nhật
        setTimeout(() => {
          resolve(userInfo);
        }, 50);
        return;
      } else if (accessToken) {
        // Chỉ gọi loadMe() khi không có userInfo
        loadMe().then(() => resolve()).catch(() => resolve());
      } else {
        setUser(null);
        setLoading(false);
        setInitialized(true);
        resolve(null);
      }

      if (accessToken) {
        scheduleWarning();
      }
    });
  };

  useEffect(() => {
    return () => {
      clearWarningTimers();
    };
  }, []);

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
      <SessionToast isOpen={showSessionWarning} onClose={handleWarningClose} />
    </AuthContext.Provider>
  );
}

// eslint-disable-next-line react-refresh/only-export-components
export function useAuth() {
  return useContext(AuthContext);
}

export default AuthProvider;

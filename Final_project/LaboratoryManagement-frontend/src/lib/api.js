import axios from "axios";
import * as notify from "./notify";
// eslint-disable-next-line no-unused-vars
import i18n from "../i18n";
import { clearLoginType } from "./loginRedirect";

const DEFAULT_BASE = "/api/v1";
const BASE = (
  import.meta.env.VITE_API_BASE_URL ||
  import.meta.env.VITE_API_URL ||
  DEFAULT_BASE
).replace(/\/+$/, "");

const REFRESH_ENDPOINT =
  import.meta.env.VITE_TOKEN_REFRESH_ENDPOINT || "/api/v1/auth/refresh";
const TESTORDER_BASE = import.meta.env.VITE_API_TESTORDER_PATIENT || "";

function buildUrl(base, endpoint) {
  if (!endpoint) return base;
  if (/^https?:\/\//i.test(endpoint)) return endpoint;
  const b = base.endsWith("/") ? base.slice(0, -1) : base;
  const e = endpoint.startsWith("/") ? endpoint : `/${endpoint}`;
  return `${b}${e}`;
}

function isPlainObject(v) {
  return Object.prototype.toString.call(v) === "[object Object]";
}

const http = axios.create({
  baseURL: BASE,
  timeout: 15000,
  withCredentials: true,
});

http.defaults.headers.common.Accept = "application/json";

const KEY_ACCESS = "lm.access";
const KEY_REFRESH = "lm.refresh";

export function getAccessToken() {
  try {
    return localStorage.getItem(KEY_ACCESS);
  } catch {
    return null;
  }
}
export function setAccessToken(token) {
  try {
    if (!token) localStorage.removeItem(KEY_ACCESS);
    else localStorage.setItem(KEY_ACCESS, token);
  } catch {
    /* empty */
  }
}
export function getRefreshToken() {
  try {
    return localStorage.getItem(KEY_REFRESH);
  } catch {
    return null;
  }
}
export function setRefreshToken(token) {
  try {
    if (!token) localStorage.removeItem(KEY_REFRESH);
    else localStorage.setItem(KEY_REFRESH, token);
  } catch {
    /* empty */
  }
}
export function clearSession() {
  try {
    localStorage.removeItem(KEY_ACCESS);
    localStorage.removeItem(KEY_REFRESH);
    sessionStorage.removeItem(KEY_ACCESS);
    sessionStorage.removeItem(KEY_REFRESH);

    // Đảm bảo xóa luôn thông tin loại đăng nhập để lần đăng nhập sau không bị "kẹt" ở sai portal
    try {
      clearLoginType();
      localStorage.removeItem("lm.loginEntryPath");
    } catch {
      /* empty */
    }

    try {
      delete http.defaults.headers.common.Authorization;
    } catch {
      /* empty */
    }

    // Phát tín hiệu logout sang các tab khác (nếu có)
    localStorage.setItem("app:logout", String(Date.now()));
    localStorage.removeItem("app:logout");
  } catch {
    /* empty */
  }
}

try {
  const t = getAccessToken();
  if (t) http.defaults.headers.common.Authorization = `Bearer ${t}`;
} catch {
  /* empty */
}

http.interceptors.request.use(
  async (config) => {
    config.meta = config.meta || {};
    if (!config.method) config.method = "get";

    // Kiểm tra xem có đang ở trang login không - nếu có và không phải public request thì cancel
    const isLoginPage =
      typeof window !== "undefined" &&
      (window.location.pathname === "/login" ||
        window.location.pathname === "/admin/login" ||
        window.location.pathname === "/");

    // Nếu đang ở trang login và request không phải public (như login, refresh), thì không thêm token
    if (isLoginPage && !config.meta.public) {
      // Chỉ cho phép các request public như login, refresh khi ở trang login
      const isPublicAuthEndpoint =
        config.url &&
        (config.url.includes("/auth/login") ||
          config.url.includes("/auth/refresh") ||
          config.url.includes("/auth/logout"));

      if (!isPublicAuthEndpoint) {
        // Cancel request nếu không phải public auth endpoint
        return Promise.reject(new Error("Request cancelled: on login page"));
      }
    }

    if (!config.meta.public) {
      const token = getAccessToken();
      if (token && String(token).trim()) {
        config.headers = {
          ...config.headers,
          Authorization: `Bearer ${token}`,
        };
      } else if (config.headers && config.headers.Authorization) {
        const { Authorization, ...rest } = config.headers;
        config.headers = rest;
      }
    }

    const m = String(config.method).toLowerCase();
    if (["post", "put", "patch"].includes(m)) {
      if (config.data == null) config.data = {};
      if (isPlainObject(config.data)) {
        config.headers = {
          ...config.headers,
          "Content-Type": "application/json",
          Accept: "application/json",
        };
      }
    }

    return config;
  },
  (err) => Promise.reject(err)
);

let isRefreshing = false;
let failedQueue = [];

function processQueue(error, token = null) {
  failedQueue.forEach((p) => (error ? p.reject(error) : p.resolve(token)));
  failedQueue = [];
}

function shouldBypassRefresh(error) {
  try {
    const status = error?.response?.status;
    const code = String(error?.response?.data?.error || "").toLowerCase();
    if (
      status === 401 &&
      (code === "token_revoked" || code === "token_revoked_userwide")
    ) {
      return true;
    }
    return false;
  } catch {
    return false;
  }
}

http.interceptors.response.use(
  (res) => res,
  async (error) => {
    const originalRequest = error?.config;
    if (!error || !error.response) return Promise.reject(error);
    const status = error.response.status;

    if (shouldBypassRefresh(error)) {
      clearSession();
      return Promise.reject(error);
    }

    const refreshUrl = (() => {
      try {
        if (/^https?:\/\//i.test(REFRESH_ENDPOINT)) return REFRESH_ENDPOINT;
        if (REFRESH_ENDPOINT.startsWith(BASE)) return REFRESH_ENDPOINT;
        return buildUrl(BASE, REFRESH_ENDPOINT);
      } catch {
        return buildUrl(BASE, REFRESH_ENDPOINT);
      }
    })();

    const originalUrlFull = (() => {
      try {
        if (!originalRequest) return "";
        const u = originalRequest.url;
        if (/^https?:\/\//i.test(u)) return u;
        const base = originalRequest.baseURL || BASE;
        return buildUrl(base, u);
      } catch {
        return originalRequest?.url || "";
      }
    })();

    const isRefreshRequest =
      originalUrlFull === refreshUrl ||
      originalUrlFull.startsWith(refreshUrl) ||
      (originalRequest?.url && originalRequest?.url.includes("/auth/refresh"));

    if (isRefreshRequest) {
      clearSession();
      return Promise.reject(error);
    }

    if (status === 401 && !originalRequest?.meta?.public) {
      if (isRefreshing) {
        return new Promise(function (resolve, reject) {
          failedQueue.push({ resolve, reject });
        })
          .then((token) => {
            if (token)
              originalRequest.headers = {
                ...originalRequest.headers,
                Authorization: `Bearer ${token}`,
              };
            return http(originalRequest);
          })
          .catch((err) => Promise.reject(err));
      }

      isRefreshing = true;
      try {
        const storedRefresh = getRefreshToken();
        const url = refreshUrl;

        const resp = storedRefresh
          ? await axios.post(
              url,
              { refreshToken: storedRefresh },
              {
                withCredentials: true,
                headers: {
                  "Content-Type": "application/json",
                  Accept: "application/json",
                },
              }
            )
          : await axios.post(
              url,
              {},
              {
                withCredentials: true,
                headers: {
                  "Content-Type": "application/json",
                  Accept: "application/json",
                },
              }
            );

        const newToken = resp?.data?.accessToken || resp?.data?.token || null;
        const newRefresh = resp?.data?.refreshToken || null;

        if (newToken) {
          setAccessToken(newToken);
          http.defaults.headers.common.Authorization = `Bearer ${newToken}`;
        }
        if (newRefresh) setRefreshToken(newRefresh);

        processQueue(null, newToken);
        isRefreshing = false;

        if (newToken) {
          originalRequest.headers = {
            ...originalRequest.headers,
            Authorization: `Bearer ${newToken}`,
          };
        }

        return http(originalRequest);
      } catch (err) {
        processQueue(err, null);
        isRefreshing = false;
        clearSession();
        return Promise.reject(err);
      }
    }

    try {
      const body = error.response?.data;
      let userMessage = null;
      if (body) {
        if (body.error) userMessage = body.error;
        else if (body.message) userMessage = body.message;
        else if (Array.isArray(body.errors))
          userMessage = body.errors.map((e) => e.message || e).join(", ");
      }
      if (!userMessage && error.message) userMessage = error.message;
      if (!originalRequest?.meta?.suppressError && userMessage) {
        const lower = String(userMessage).toLowerCase();
        if (lower.includes("internal server") || status >= 500) {
          notify.modalError("Lỗi hệ thống", userMessage);
        } else if (status === 409 || status === 400 || status === 422) {
          notify.warn(userMessage);
        } else {
          notify.error(userMessage);
        }
      }
    } catch {
      /* empty */
    }

    return Promise.reject(error);
  }
);

export default http;

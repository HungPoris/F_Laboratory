import React, { useState, useEffect, useRef } from "react";
import { Eye, EyeOff, Lock, User, Shield, AlertTriangle } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "../lib";
import { useTranslation } from "react-i18next";
import http, { clearSession } from "../lib/api";
import Loading from "../components/Loading";
import { setAccessToken, setRefreshToken } from "../lib/auth";
import { setLoginType, clearLoginType } from "../lib/loginRedirect";
import * as notify from "../lib/notify";
import "../i18n";

export default function AdminLogin() {
  const { t } = useTranslation();
  const nav = useNavigate();
  const { loginWithToken, user } = useAuth();

  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [rememberMe, setRememberMe] = useState(false);
  const [loading, setLoading] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [loginSuccess, setLoginSuccess] = useState(false);
  const [formError, setFormError] = useState(null);

  const [displayText, setDisplayText] = useState("");
  const [currentTextIndex, setCurrentTextIndex] = useState(0);
  const fullText = "administrator access";

  const isSubmittingRef = useRef(false);

  // Xóa loginType cũ và clear session khi truy cập trang admin login để đảm bảo loại login mới được set đúng
  useEffect(() => {
    clearLoginType();
    // Clear session và token khi vào trang login để tránh gọi API không cần thiết
    try {
      clearSession();
      delete http.defaults.headers.common.Authorization;
    } catch {
      /* empty */
    }
  }, []);

  useEffect(() => {
    try {
      const savedUsername = localStorage.getItem("admin_remembered_username");
      const savedRemember = localStorage.getItem("admin_remember_me");
      if (savedRemember === "true" && savedUsername) {
        setUsername(savedUsername);
        setRememberMe(true);
      }
    } catch {
      /* empty */
    }
  }, []);

  useEffect(() => {
    if (user && user.roles?.includes("ADMIN")) {
      nav("/admin/users", { replace: true });
    }
  }, [user, nav]);

  useEffect(() => {
    if (currentTextIndex < fullText.length) {
      const tmo = setTimeout(() => {
        setDisplayText((prev) => prev + fullText[currentTextIndex]);
        setCurrentTextIndex((prev) => prev + 1);
      }, 100);
      return () => clearTimeout(tmo);
    }
  }, [currentTextIndex]);

  function resolveErrorMessage(responseData, httpStatus = null) {
    const toCode = (x) =>
      typeof x === "string" && x.trim() ? x.trim().toUpperCase() : null;

    if (!responseData || typeof responseData !== "object") {
      if (httpStatus === 401) return t("errors.INVALID_CREDENTIALS");
      if (httpStatus === 423) return t("errors.ACCOUNT_LOCKED");
      if (httpStatus === 403) return t("errors.FORBIDDEN");
      if (httpStatus === 500) return t("errors.GENERAL_ERROR");
      return t("errors.UNKNOWN_ERROR");
    }

    let code = null;

    if (!code && typeof responseData.error === "string")
      code = toCode(responseData.error);
    if (!code && typeof responseData.code === "string")
      code = toCode(responseData.code);
    if (
      !code &&
      typeof responseData.message === "string" &&
      /^[A-Za-z0-9_]+$/.test(responseData.message.trim())
    )
      code = toCode(responseData.message);

    if (!code && Array.isArray(responseData.fieldErrors)) {
      const fe = responseData.fieldErrors.find(
        (x) => x && typeof x.code === "string" && x.code.trim()
      );
      if (fe) code = toCode(fe.code);
    }

    if (
      !code &&
      responseData.errors &&
      typeof responseData.errors === "object"
    ) {
      try {
        const vals = Object.values(responseData.errors).flat();
        const first =
          vals.find((v) => typeof v === "string" && v.trim()) ||
          (
            vals.find(
              (v) => v && typeof v.code === "string" && v.code.trim()
            ) || {}
          ).code;
        if (first) code = toCode(first);
      } catch {
        /* empty */
      }
    }

    if (!code && httpStatus === 401) code = "INVALID_CREDENTIALS";
    if (!code && httpStatus === 423) code = "ACCOUNT_LOCKED";
    if (!code && httpStatus === 403) code = "FORBIDDEN";
    if (!code && httpStatus === 500) code = "GENERAL_ERROR";

    if (code) {
      const i18nKey = `errors.${code}`;
      const i18nMsg = t(i18nKey, { defaultValue: "" });
      if (i18nMsg && i18nMsg !== i18nKey) return i18nMsg;
    }

    return t("errors.UNKNOWN_ERROR");
  }

  const API_BASE = (
    import.meta.env.VITE_API_BASE_URL ||
    import.meta.env.VITE_API_URL ||
    ""
  ).replace(/\/+$/, "");
  const LOGIN_ENDPOINT =
    (API_BASE ? API_BASE : "") +
    (import.meta.env.VITE_LOGIN_ENDPOINT || "/api/v1/auth/login");

  async function doLoginRequest(payload) {
    return http.post(LOGIN_ENDPOINT, payload, {
      meta: {
        public: true,
        suppressError: true,
      },
    });
  }

  async function submit(e) {
    e.preventDefault();
    if (isSubmittingRef.current) return;
    setFormError(null);

    if (!username) {
      const msg = t("errors.USERNAME_REQUIRED");
      setFormError(msg);
      notify.warn(msg);
      return;
    }
    if (!password) {
      const msg = t("errors.PASSWORD_REQUIRED");
      setFormError(msg);
      notify.warn(msg);
      return;
    }

    try {
      if (rememberMe) {
        localStorage.setItem("admin_remembered_username", username);
        localStorage.setItem("admin_remember_me", "true");
      } else {
        localStorage.removeItem("admin_remembered_username");
        localStorage.removeItem("admin_remember_me");
      }
    } catch {
      /* empty */
    }

    setLoading(true);
    isSubmittingRef.current = true;

    try {
      const payload = { username, password };

      let response = null;
      // eslint-disable-next-line no-useless-catch
      try {
        response = await doLoginRequest(payload);
      } catch (err) {
        throw err;
      }

      if (!response) throw new Error("NO_RESPONSE");

      const data = response?.data || response;
      const tk = data?.token || data?.accessToken || data?.access_token;
      const refresh =
        data?.refreshToken || data?.refresh || data?.refresh_token;

      if (tk) {
        setAccessToken(tk);
        if (refresh) setRefreshToken(refresh);

        // Lưu loại login là admin
        setLoginType("admin");

        const mustChange =
          data.mustChangePassword || data.user?.mustChangePassword;

        if (mustChange === true) {
          notify.info(
            t("auth.must_change_password_first", {
              defaultValue:
                "You must change your password before accessing the system",
            })
          );

          setTimeout(() => {
            nav("/change-password-first-login", {
              replace: true,
              state: {
                isFirstLogin: true,
                username: username,
                loginType: "admin",
              },
            });
          }, 800);
          return;
        }

        try {
          const meRes = await http.get("/api/v1/auth/me");
          const meData = meRes?.data;
          const userRoles = meData?.roles || [];

          if (!userRoles.includes("ADMIN")) {
            clearSession();
            delete http.defaults.headers.common.Authorization;

            const msg =
              "Access denied. This portal is for administrators only.";
            setFormError(msg);
            notify.error(msg);
            setLoading(false);
            isSubmittingRef.current = false;
            return;
          }

          const screensRes = await http.get("/api/v1/ui/accessible-screens");
          const accessibleScreens = screensRes?.data?.accessible_screens || [];

          try {
            await loginWithToken(tk, refresh, {
              ...meData,
              accessibleScreens: accessibleScreens,
            });
          } catch {
            /* empty */
          }

          await new Promise((resolve) => setTimeout(resolve, 100));

          setLoginSuccess(true);
          notify.success("Admin login successful");

          const allScreensRes = await http.get("/api/v1/screens/all");
          let allScreens = allScreensRes?.data || [];

          allScreens = allScreens.sort(
            (a, b) => (a.ordering || 999) - (b.ordering || 999)
          );

          const adminScreens = [
            "ADMIN_USERS_LIST",
            "ADMIN_ROLES_LIST",
            "ADMIN_PRIVILEGES_LIST",
          ];

          const firstAdminScreen = allScreens
            .filter(
              (s) =>
                adminScreens.includes(s.screen_code) &&
                accessibleScreens.includes(s.screen_code)
            )
            .sort((a, b) => {
              const prioA = adminScreens.indexOf(a.screen_code);
              const prioB = adminScreens.indexOf(b.screen_code);
              return prioA - prioB;
            })[0];

          if (firstAdminScreen) {
            window.location.href = firstAdminScreen.path;
          } else {
            window.location.href = "/admin/users";
          }
          // eslint-disable-next-line no-unused-vars
        } catch (err) {
          window.location.href = "/admin/users";
        }
      } else {
        const msg = resolveErrorMessage(data);
        setFormError(msg);
        notify.warn(msg);
        setLoading(false);
        isSubmittingRef.current = false;
      }
    } catch (err) {
      const data = err?.response?.data;
      const msg = resolveErrorMessage(data || {}, err?.response?.status);
      setFormError(msg);
      if (err?.response?.status >= 500) {
        notify.modalError(t("admin.error") || "Error", msg);
      } else {
        notify.warn(msg);
      }
      setLoading(false);
      isSubmittingRef.current = false;
    }
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-[#0a1929] via-[#0d2137] to-[#051120] flex items-center justify-center px-4 py-6 md:py-10 overflow-hidden">
      {loginSuccess && (
        <div className="fixed inset-0 bg-gradient-to-br from-[#0a1929] to-[#051120] z-50 flex items-center justify-center animate-fade-in">
          <div className="text-center animate-scale-in">
            <div className="w-24 h-24 bg-white rounded-full flex items-center justify-center mb-6 mx-auto animate-bounce-once">
              <svg
                className="w-12 h-12 text-blue-600"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth="3"
                  d="M5 13l4 4L19 7"
                />
              </svg>
            </div>
            <h2 className="text-4xl font-bold text-white mb-4">
              Welcome, Administrator
            </h2>
            <p className="text-xl text-white/90">Accessing admin panel...</p>
          </div>
        </div>
      )}

      <div className="w-full max-w-6xl mx-auto grid lg:grid-cols-2 gap-8 lg:gap-12 items-center">
        {/* Left Side - Admin Info */}
        <div className="hidden lg:block space-y-8">
          <div
            className="animate-slide-in-left"
            style={{ animationDelay: "0.2s" }}
          >
            <div className="inline-flex items-center gap-3 bg-[#0d2137]/80 backdrop-blur-sm px-5 py-3 rounded-full shadow-md mb-6 border border-[#1a3a52]">
              <div className="w-10 h-10 bg-gradient-to-br from-blue-500 to-indigo-600 rounded-full flex items-center justify-center">
                <Shield className="w-6 h-6 text-white" />
              </div>
              <span className="font-bold text-xl text-white">
                F-Laboratory Admin
              </span>
            </div>
            <h1 className="text-5xl font-bold text-white mb-4 leading-tight">
              Secure access,
              <br />
              <span className="bg-gradient-to-r from-blue-300 via-cyan-300 to-indigo-300 bg-clip-text text-transparent inline-block min-w-[400px]">
                {displayText}
                <span className="animate-blink">|</span>
              </span>
              <br />
              control panel
            </h1>
          </div>

          <div
            className="animate-slide-in-left"
            style={{ animationDelay: "0.5s" }}
          >
            <p className="text-lg text-slate-100 mb-6 leading-relaxed">
              Administrator portal — manage users, configure system settings,
              monitor activities, and control access permissions across the
              entire laboratory platform.
            </p>
            <div className="space-y-3 text-slate-50">
              {[
                "Full system administration",
                "Advanced security controls",
                "Real-time activity monitoring",
              ].map((text, i) => (
                <div
                  key={i}
                  className="flex items-center gap-3 animate-slide-in-left"
                  style={{ animationDelay: `${0.7 + i * 0.1}s` }}
                >
                  <div className="w-5 h-5 rounded-full border-2 border-blue-300 flex items-center justify-center">
                    <div className="w-2 h-2 bg-blue-300 rounded-full" />
                  </div>
                  <span>{text}</span>
                </div>
              ))}
            </div>
          </div>

          <div
            className="bg-[#0d2137] border border-[#1a3a52] rounded-2xl shadow-lg p-5 md:p-6 max-w-md animate-float"
            style={{ animationDelay: "1s" }}
          >
            <div className="flex gap-2 mb-4">
              <div className="w-3 h-3 rounded-full bg-red-500 animate-pulse" />
              <div className="w-3 h-3 rounded-full bg-yellow-500 animate-pulse" />
              <div className="w-3 h-3 rounded-full bg-green-500 animate-pulse" />
            </div>
            <div className="flex gap-4">
              <div className="w-32 h-24 bg-gradient-to-br from-blue-500 via-indigo-600 to-slate-700 rounded-xl animate-gradient" />
              <div className="flex-1 space-y-2">
                <div className="h-3 bg-slate-600 rounded-full w-full animate-pulse" />
                <div className="h-3 bg-slate-600 rounded-full w-3/4 animate-pulse" />
                <div className="h-3 bg-slate-600 rounded-full w-5/6 animate-pulse" />
              </div>
            </div>
          </div>
        </div>

        {/* Right Side - Login Form */}
        <div
          className="w-full max-w-lg mx-auto animate-pop-in"
          style={{ animationDelay: "0.4s" }}
        >
          <div className="bg-white rounded-3xl shadow-xl p-8 md:p-10 transform transition-all duration-300 hover:shadow-2xl">
            <div className="mb-6">
              <div className="inline-flex items-center justify-center w-16 h-16 bg-gradient-to-br from-blue-500 to-indigo-600 rounded-2xl mb-4 shadow-lg">
                <Shield className="w-8 h-8 text-white" />
              </div>
              <h3 className="text-2xl md:text-3xl font-bold text-gray-800 mb-2">
                Admin Portal
              </h3>
              <p className="text-gray-500 text-sm">Authorized personnel only</p>
              <div className="mt-4 inline-flex items-center gap-2 px-4 py-2 bg-amber-50 border border-amber-200 rounded-lg">
                <AlertTriangle className="w-4 h-4 text-amber-600" />
                <span className="text-xs text-amber-800 font-medium">
                  Administrator access required
                </span>
              </div>
            </div>

            <form onSubmit={submit} className="space-y-5">
              <div className="transition-all duration-300 hover:translate-x-1">
                <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                  <User className="w-4 h-4" />
                  Admin Username
                </label>
                <input
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  required
                  placeholder="Enter admin username"
                  className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-600 focus:border-transparent transition-all bg-slate-50"
                />
              </div>

              <div className="transition-all duration-300 hover:translate-x-1">
                <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                  <Lock className="w-4 h-4" />
                  Admin Password
                </label>
                <div className="relative">
                  <input
                    type={showPassword ? "text" : "password"}
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    required
                    placeholder="Enter admin password"
                    className="w-full px-4 py-3 pr-12 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-600 focus:border-transparent transition-all bg-slate-50"
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute right-4 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600 transition-colors"
                  >
                    {showPassword ? (
                      <EyeOff className="w-5 h-5" />
                    ) : (
                      <Eye className="w-5 h-5" />
                    )}
                  </button>
                </div>
              </div>

              {formError && (
                <div className="p-4 bg-red-50 border border-red-200 rounded-lg">
                  <p className="text-sm text-red-600">{formError}</p>
                </div>
              )}

              <div className="flex items-center justify-between text-sm pt-1">
                <label className="flex items-center gap-2 cursor-pointer group">
                  <input
                    type="checkbox"
                    checked={rememberMe}
                    onChange={(e) => setRememberMe(e.target.checked)}
                    className="w-4 h-4 text-blue-600 border-gray-300 rounded focus:ring-blue-500 focus:ring-2 cursor-pointer"
                  />
                  <span className="text-gray-600 group-hover:text-gray-800 transition-colors">
                    Remember me
                  </span>
                </label>
              </div>

              <button
                type="submit"
                disabled={loading}
                className="w-full py-3.5 bg-gradient-to-r from-blue-600 to-indigo-600 text-white font-semibold rounded-lg hover:shadow-lg hover:shadow-blue-300/50 transition-all hover:scale-105 active:scale-95 disabled:opacity-70 disabled:cursor-not-allowed"
              >
                {loading ? <Loading size={22} /> : "Login to Admin Portal"}
              </button>
            </form>

            <div className="mt-6 text-center">
              <button
                type="button"
                onClick={() => {
                  // Set flag để Login page biết cần reload
                  try {
                    sessionStorage.setItem("lm.shouldReloadLogin", "true");
                  } catch {
                    /* empty */
                  }
                  nav("/login");
                }}
                className="text-sm text-gray-600 hover:text-gray-800 transition-colors"
              >
                ← Back to regular login
              </button>
            </div>
          </div>

          <div
            className="mt-6 text-center text-xs text-slate-300 animate-fade-in"
            style={{ animationDelay: "1.2s" }}
          >
            © 2025 F-Laboratory Cloud — Admin Portal
          </div>
        </div>
      </div>

      <style>{`
        @keyframes slide-in-left { from { opacity: 0; transform: translateX(-50px); } to { opacity: 1; transform: translateX(0); } }
        @keyframes pop-in { 0% { opacity: 0; transform: scale(0.8) translateY(20px); } 50% { transform: scale(1.05); } 100% { opacity: 1; transform: scale(1) translateY(0); } }
        @keyframes fade-in { from { opacity: 0; } to { opacity: 1; } }
        @keyframes float { 0%,100% { transform: translateY(0); } 50% { transform: translateY(-10px); } }
        @keyframes blink { 0%,100% { opacity: 1; } 50% { opacity: 0; } }
        @keyframes gradient { 0% { background-position: 0% 50%; } 50% { background-position: 100% 50%; } 100% { background-position: 0% 50%; } }
        @keyframes scale-in { from { transform: scale(0); } to { transform: scale(1); } }
        @keyframes bounce-once { 0%,100% { transform: translateY(0); } 25% { transform: translateY(-20px); } 50% { transform: translateY(0); } 75% { transform: translateY(-10px); } }
        .animate-slide-in-left { animation: slide-in-left .6s ease-out forwards; opacity: 0; }
        .animate-pop-in { animation: pop-in .6s cubic-bezier(.175,.885,.32,1.275) forwards; opacity: 0; }
        .animate-fade-in { animation: fade-in .6s ease-out forwards; opacity: 0; }
        .animate-float { animation: float 3s ease-in-out infinite; }
        .animate-blink { animation: blink 1s step-end infinite; }
        .animate-gradient { background-size: 200% 200%; animation: gradient 3s ease infinite; }
        .animate-scale-in { animation: scale-in .5s cubic-bezier(.175,.885,.32,1.275); }
        .animate-bounce-once { animation: bounce-once 1s ease; }
      `}</style>
    </div>
  );
}

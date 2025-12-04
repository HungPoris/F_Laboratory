import React, { useState, useEffect, useRef } from "react";
import { Eye, EyeOff, Lock, User } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "../lib";
import { useTranslation } from "react-i18next";
import http, { clearSession, getAccessToken } from "../lib/api";
import Loading from "../components/Loading";
import { setAccessToken, setRefreshToken } from "../lib/auth";
import { setLoginType, clearLoginType } from "../lib/loginRedirect";
import * as notify from "../lib/notify";
import "../i18n";

export default function Login() {
  const { t } = useTranslation();
  const nav = useNavigate();
  const { loginWithToken } = useAuth();

  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [rememberMe, setRememberMe] = useState(false);
  const [loading, setLoading] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [loginSuccess, setLoginSuccess] = useState(false);
  const [formError, setFormError] = useState(null);

  const [displayText, setDisplayText] = useState("");
  const [currentTextIndex, setCurrentTextIndex] = useState(0);
  const fullText = "accelerate your work";

  const isSubmittingRef = useRef(false);
  const hasReloadedRef = useRef(false);

  useEffect(() => {
    // Kiểm tra xem có flag skip reload không (được set khi redirect sau login thành công)
    const skipReload = sessionStorage.getItem("lm.skipReloadLogin") === "true";

    if (skipReload) {
      // Xóa flag và không clear session vì đang trong quá trình redirect sau login
      try {
        sessionStorage.removeItem("lm.skipReloadLogin");
      } catch {
        /* empty */
      }
      // Không clear session nếu đang trong quá trình redirect sau login
      return;
    }

    // Tự động reload trang khi navigate từ trang khác
    // (không reload khi đã dùng window.location vì đã reload rồi)
    if (!hasReloadedRef.current) {
      // Kiểm tra xem có navigate từ trang khác không
      const hasReferrer = document.referrer && document.referrer.trim() !== "";
      const referrerUrl = hasReferrer ? new URL(document.referrer) : null;
      const currentUrl = new URL(window.location.href);
      const isFromOtherPage =
        hasReferrer &&
        referrerUrl.origin === currentUrl.origin &&
        referrerUrl.pathname !== currentUrl.pathname;

      // Reload nếu:
      // 1. Có flag shouldReload (được set khi navigate bằng React Router)
      // 2. Hoặc navigate từ trang khác (có referrer và khác pathname)
      const shouldReload =
        sessionStorage.getItem("lm.shouldReloadLogin") === "true" ||
        isFromOtherPage;

      if (shouldReload) {
        hasReloadedRef.current = true;
        // Xóa flag sau khi đã kiểm tra
        try {
          sessionStorage.removeItem("lm.shouldReloadLogin");
        } catch {
          /* empty */
        }
        // Reload trang để đảm bảo tất cả request được khởi tạo lại
        window.location.reload();
        return;
      }
    }

    // Chỉ clear session nếu không có token (chưa login thành công)
    const hasToken = getAccessToken();
    if (!hasToken) {
      clearLoginType();
      clearSession();

      try {
        delete http.defaults.headers.common.Authorization;
        localStorage.removeItem("lm.access");
        localStorage.removeItem("lm.refresh");
        sessionStorage.removeItem("lm.access");
        sessionStorage.removeItem("lm.refresh");
      } catch {
        /* empty */
      }
    }
  }, []);

  useEffect(() => {
    try {
      const savedUsername = localStorage.getItem("remembered_username");
      const savedRemember = localStorage.getItem("remember_me");
      if (savedRemember === "true" && savedUsername) {
        setUsername(savedUsername);
        setRememberMe(true);
      }
    } catch {
      /* empty */
    }
  }, []);

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
        localStorage.setItem("remembered_username", username);
        localStorage.setItem("remember_me", "true");
      } else {
        localStorage.removeItem("remembered_username");
        localStorage.removeItem("remember_me");
      }
    } catch {
      /* empty */
    }

    setLoading(true);
    isSubmittingRef.current = true;

    try {
      const payload = { username, password };
      const response = await doLoginRequest(payload);

      if (!response) throw new Error("NO_RESPONSE");

      const data = response?.data || response;
      const tk = data?.token || data?.accessToken || data?.access_token;
      const refresh =
        data?.refreshToken || data?.refresh || data?.refresh_token;

      if (tk) {
        const userRoles = data.roles || data.user?.roles || [];
        const isAdmin = userRoles.some((role) =>
          typeof role === "string" ? role.toUpperCase() === "ADMIN" : false
        );

        if (isAdmin) {
          setLoading(false);
          isSubmittingRef.current = false;

          const errorMsg =
            "This account has administrator privileges. Please use the Admin Login page.";
          setFormError(errorMsg);
          notify.error(errorMsg);

          setTimeout(() => {
            if (
              window.confirm("Would you like to go to the Admin Login page?")
            ) {
              nav("/admin/login");
            }
          }, 500);

          return;
        }

        setAccessToken(tk);
        if (refresh) setRefreshToken(refresh);
        http.defaults.headers.common.Authorization = `Bearer ${tk}`;
        setLoginType("user");

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
                loginType: "user",
              },
            });
          }, 800);
          return;
        }

        setLoginSuccess(true);
        notify.success("Login success");

        try {
          let accessibleScreens = [];
          try {
            const screensRes = await http.get("/api/v1/ui/accessible-screens");
            accessibleScreens = screensRes?.data?.accessible_screens || [];
          } catch (err) {
            console.error("Error fetching accessible screens:", err);
          }

          // Đảm bảo loginWithToken hoàn thành trước khi redirect
          await loginWithToken(tk, refresh, {
            id: data.user?.id || data.id,
            username: data.user?.username || data.username || username,
            fullName:
              data.user?.fullName ||
              data.fullName ||
              data.user?.username ||
              data.username ||
              username,
            roles: userRoles,
            privileges: data.privileges || data.user?.privileges || [],
            accessibleScreens: accessibleScreens,
          });

          // Đợi thêm một chút để đảm bảo state đã được cập nhật hoàn toàn
          await new Promise((resolve) => setTimeout(resolve, 300));

          // Set flag để tránh reload khi redirect
          try {
            sessionStorage.setItem("lm.skipReloadLogin", "true");
          } catch {
            /* empty */
          }

          if (
            userRoles.includes("LAB_TECH") ||
            userRoles.includes("LAB_MANAGER")
          ) {
            window.location.replace("/patients");
            return;
          }

          const allScreensRes = await http.get("/api/v1/screens/all");
          let allScreens = allScreensRes?.data || [];

          const excludedScreenCodes = [
            "LANDING_PAGE",
            "SCR_LANDING",
            "LOGIN",
            "SCR_LOGIN",
            "ADMIN_LOGIN",
            "SCR_ADMIN_LOGIN",
          ];

          allScreens = allScreens.sort(
            (a, b) => (a.ordering || 999) - (b.ordering || 999)
          );

          const dashboardPriority = {
            PATIENTS: 1,
            PATIENT_LIST: 1,
            ADMIN_USERS_LIST: 2,
            ADMIN_ROLES_LIST: 3,
            ADMIN_PRIVILEGES_LIST: 4,
            LAB_MANAGER_HOME: 5,
            LAB_TECH_HOME: 6,
            LAB_USER_HOME: 7,
            SERVICE_HOME: 8,
            USER_HOME: 99,
          };

          const firstAccessibleScreen = allScreens
            .filter(
              (s) =>
                accessibleScreens.includes(s.screen_code) &&
                !s.is_public &&
                !excludedScreenCodes.includes(s.screen_code)
            )
            .sort((a, b) => {
              const prioA =
                dashboardPriority[a.screen_code] || a.ordering || 999;
              const prioB =
                dashboardPriority[b.screen_code] || b.ordering || 999;
              return prioA - prioB;
            })[0];

          if (firstAccessibleScreen) {
            window.location.replace(firstAccessibleScreen.path);
          } else {
            window.location.replace("/patients");
          }
        } catch (err) {
          console.error("Post-login error:", err);
          window.location.replace("/patients");
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
    <div className="min-h-screen bg-gradient-to-br from-blue-50 via-cyan-50 to-emerald-50 flex items-center justify-center px-4 py-6 md:py-10 overflow-hidden">
      {loginSuccess && (
        <div className="fixed inset-0 bg-gradient-to-br from-blue-600 to-emerald-500 z-50 flex items-center justify-center animate-fade-in">
          <div className="text-center animate-scale-in">
            <div className="w-24 h-24 bg-white rounded-full flex items-center justify-center mb-6 mx-auto animate-bounce-once">
              <svg
                className="w-12 h-12 text-emerald-500"
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
              Welcome Back!
            </h2>
            <p className="text-xl text-white/90">
              Redirecting to your dashboard...
            </p>
          </div>
        </div>
      )}

      <div className="w-full max-w-6xl mx-auto grid lg:grid-cols-2 gap-8 lg:gap-12 items-center">
        <div className="hidden lg:block space-y-8">
          <div
            className="animate-slide-in-left"
            style={{ animationDelay: "0.2s" }}
          >
            <div className="inline-flex items-center gap-3 bg-white px-5 py-3 rounded-full shadow-md mb-6">
              <div className="w-10 h-10 bg-gradient-to-br from-blue-500 to-emerald-500 rounded-full flex items-center justify-center">
                <span className="text-white font-bold text-lg">F</span>
              </div>
              <span className="font-bold text-xl text-gray-800">
                F-Laboratory Cloud
              </span>
            </div>
            <h1 className="text-5xl font-bold text-gray-800 mb-4 leading-tight">
              Welcome back,
              <br />
              <span className="bg-gradient-to-r from-blue-600 via-cyan-500 to-emerald-500 bg-clip-text text-transparent inline-block min-w-[400px]">
                {displayText}
                <span className="animate-blink">|</span>
              </span>
              <br />
              to your lab
            </h1>
          </div>

          <div
            className="animate-slide-in-left"
            style={{ animationDelay: "0.5s" }}
          >
            <p className="text-lg text-gray-600 mb-6 leading-relaxed">
              One account – connect your entire laboratory workflow: Sample
              Reception, Equipment Management, Result Tracking, and Analysis
              Reporting.
            </p>
            <div className="space-y-3 text-gray-700">
              {[
                "Enterprise-grade security",
                "Optimized performance",
                "99.9% uptime guaranteed",
              ].map((text, i) => (
                <div
                  key={i}
                  className="flex items-center gap-3 animate-slide-in-left"
                  style={{ animationDelay: `${0.7 + i * 0.1}s` }}
                >
                  <div className="w-5 h-5 rounded-full border-2 border-gray-400 flex items-center justify-center">
                    <div className="w-2 h-2 bg-gray-400 rounded-full" />
                  </div>
                  <span>{text}</span>
                </div>
              ))}
            </div>
          </div>

          <div
            className="bg-white rounded-2xl shadow-lg p-5 md:p-6 max-w-md animate-float"
            style={{ animationDelay: "1s" }}
          >
            <div className="flex gap-2 mb-4">
              <div className="w-3 h-3 rounded-full bg-red-400 animate-pulse" />
              <div className="w-3 h-3 rounded-full bg-yellow-400 animate-pulse" />
              <div className="w-3 h-3 rounded-full bg-green-400 animate-pulse" />
            </div>
            <div className="flex gap-4">
              <div className="w-32 h-24 bg-gradient-to-br from-emerald-400 via-cyan-400 to-blue-400 rounded-xl animate-gradient" />
              <div className="flex-1 space-y-2">
                <div className="h-3 bg-gray-200 rounded-full w-full animate-pulse" />
                <div className="h-3 bg-gray-200 rounded-full w-3/4 animate-pulse" />
                <div className="h-3 bg-gray-200 rounded-full w-5/6 animate-pulse" />
              </div>
            </div>
          </div>
        </div>

        <div
          className="w-full max-w-lg mx-auto animate-pop-in"
          style={{ animationDelay: "0.4s" }}
        >
          <div className="bg-white rounded-3xl shadow-xl p-8 md:p-10 transform transition-all duration-300 hover:shadow-2xl">
            <div className="mb-6">
              <h3 className="text-2xl md:text-3xl font-bold text-gray-800 mb-2">
                {t("Login")}
              </h3>
              <p className="text-gray-500 text-sm">
                Enter your credentials to continue
              </p>
            </div>

            <form onSubmit={submit} className="space-y-5">
              <div className="transition-all duration-300 hover:translate-x-1">
                <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                  <User className="w-4 h-4" />
                  Username
                </label>
                <input
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  required
                  placeholder="Enter your username"
                  className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all bg-slate-50"
                />
              </div>

              <div className="transition-all duration-300 hover:translate-x-1">
                <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                  <Lock className="w-4 h-4" />
                  Password
                </label>
                <div className="relative">
                  <input
                    type={showPassword ? "text" : "password"}
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    required
                    placeholder="Enter your password"
                    className="w-full px-4 py-3 pr-12 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all bg-slate-50"
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
                <button
                  type="button"
                  onClick={() => nav("/forgot-password")}
                  className="text-blue-600 hover:text-blue-700 font-medium transition-colors"
                >
                  Forgot password?
                </button>
              </div>

              <button
                type="submit"
                disabled={loading}
                className="w-full py-3.5 bg-gradient-to-r from-blue-500 to-emerald-500 text-white font-semibold rounded-lg hover:shadow-lg hover:shadow-blue-200 transition-all hover:scale-105 active:scale-95 disabled:opacity-70 disabled:cursor-not-allowed"
              >
                {loading ? <Loading size={22} /> : t("Login")}
              </button>
            </form>
          </div>

          <div
            className="mt-6 text-center text-xs text-gray-500 animate-fade-in"
            style={{ animationDelay: "1.2s" }}
          >
            © 2025 F-Laboratory Cloud – Security • Terms • Support
          </div>
        </div>
      </div>

      <style>{`
        @keyframes slide-in-left { from { opacity: 0; transform: translateX(-50px); } to { opacity: 1; transform: translateX(0); } }
        @keyframes pop-in { 0% { opacity: 0; transform: scale(0.8) translateY(20px); } 50% { transform: scale(1.05); } 100% { opacity: 1; transform: scale(1) translateY(0); } }
        @keyframes fade-in { from { opacity: 0; } to { opacity: 1; } }
        @keyframes bounce-in { 0% { opacity: 0; transform: scale(0.3); } 50% { transform: scale(1.1); } 100% { opacity: 1; transform: scale(1); } }
        @keyframes float { 0%,100% { transform: translateY(0); } 50% { transform: translateY(-10px); } }
        @keyframes blink { 0%,100% { opacity: 1; } 50% { opacity: 0; } }
        @keyframes gradient { 0% { background-position: 0% 50%; } 50% { background-position: 100% 50%; } 100% { background-position: 0% 50%; } }
        @keyframes scale-in { from { transform: scale(0); } to { transform: scale(1); } }
        @keyframes bounce-once { 0%,100% { transform: translateY(0); } 25% { transform: translateY(-20px); } 50% { transform: translateY(0); } 75% { transform: translateY(-10px); } }
        .animate-slide-in-left { animation: slide-in-left .6s ease-out forwards; opacity: 0; }
        .animate-pop-in { animation: pop-in .6s cubic-bezier(.175,.885,.32,1.275) forwards; opacity: 0; }
        .animate-fade-in { animation: fade-in .6s ease-out forwards; opacity: 0; }
        .animate-bounce-in { animation: bounce-in .6s ease-out forwards; opacity: 0; }
        .animate-float { animation: float 3s ease-in-out infinite; }
        .animate-blink { animation: blink 1s step-end infinite; }
        .animate-gradient { background-size: 200% 200%; animation: gradient 3s ease infinite; }
        .animate-scale-in { animation: scale-in .5s cubic-bezier(.175,.885,.32,1.275); }
        .animate-bounce-once { animation: bounce-once 1s ease; }
      `}</style>
    </div>
  );
}

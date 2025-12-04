import React, { useEffect, useState } from "react";
import { useLocation, useNavigate, useParams } from "react-router-dom";
import {
  Lock,
  Eye,
  EyeOff,
  Shield,
  Check,
  X,
  CheckCircle,
  XCircle,
  AlertCircle,
} from "lucide-react";
import http from "../lib/api";
import Loading from "../components/Loading";
import { useTranslation } from "react-i18next";

export default function ForgotReset() {
  const { t } = useTranslation();
  const nav = useNavigate();
  const loc = useLocation();
  const params = useParams();

  const storedIdentifier = (() => {
    try {
      if (loc.state?.identifier) return loc.state.identifier;
      const raw = localStorage.getItem("forgot_identifier");
      return raw ? JSON.parse(raw) : "";
    } catch {
      return "";
    }
  })();

  const initialIdentifier = (() => {
    if (storedIdentifier && Object.keys(storedIdentifier).length)
      return storedIdentifier;
    const token = params?.token || null;
    if (token) {
      return { userId: null, correlationId: token, identifier: token };
    }
    return storedIdentifier;
  })();

  const [identifier, setIdentifier] = useState(initialIdentifier);
  const [toast, setToast] = useState(null);

  useEffect(() => {
    if (loc.state?.identifier) {
      try {
        localStorage.setItem(
          "forgot_identifier",
          JSON.stringify(loc.state.identifier)
        );
      } catch {
        /* empty */
      }
      setIdentifier(loc.state.identifier);
      return;
    }

    const token = params?.token || null;
    if ((!identifier || !identifier.correlationId) && token) {
      const identObj = {
        userId: null,
        correlationId: token,
        identifier: token,
        sentAt: Date.now(),
      };
      try {
        localStorage.setItem("forgot_identifier", JSON.stringify(identObj));
      } catch {
        /* empty */
      }
      setIdentifier(identObj);
    }
  }, [identifier, loc.state, params?.token]);

  useEffect(() => {
    if (toast) {
      const timer = setTimeout(() => {
        setToast(null);
      }, 4000);
      return () => clearTimeout(timer);
    }
  }, [toast]);

  function extractIds(id) {
    if (!id) return { userId: null, correlationId: null };
    if (typeof id === "object") {
      return {
        userId: id.userId || id.user_id || null,
        correlationId:
          id.correlationId ||
          id.correlation_id ||
          id.requestId ||
          id.correlation ||
          null,
      };
    }
    if (typeof id === "string") {
      try {
        const parsed = JSON.parse(id);
        if (typeof parsed === "object") {
          return {
            userId: parsed.userId || parsed.user_id || null,
            correlationId:
              parsed.correlationId ||
              parsed.correlation_id ||
              parsed.requestId ||
              parsed.correlation ||
              null,
          };
        }
      } catch {
        /* empty */
      }
      return { userId: id, correlationId: null };
    }
    return { userId: null, correlationId: null };
  }

  const { userId, correlationId } = extractIds(identifier);

  const [p, setP] = useState("");
  const [c, setC] = useState("");
  const [l, setL] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirmPassword, setShowConfirmPassword] = useState(false);
  const [resetSuccess, setResetSuccess] = useState(false);

  const [displayText, setDisplayText] = useState("");
  const [currentTextIndex, setCurrentTextIndex] = useState(0);
  const fullText = "Reset your password";

  useEffect(() => {
    if (currentTextIndex < fullText.length) {
      const tId = setTimeout(() => {
        setDisplayText((prev) => prev + fullText[currentTextIndex]);
        setCurrentTextIndex((prev) => prev + 1);
      }, 80);
      return () => clearTimeout(tId);
    }
  }, [currentTextIndex]);

  const showToast = (message, type = "success") => {
    setToast({ message, type });
  };

  const passwordRules = [
    { label: "At least 8 characters", check: (pw) => pw.length >= 8 },
    { label: "Contains uppercase letter", check: (pw) => /[A-Z]/.test(pw) },
    { label: "Contains lowercase letter", check: (pw) => /[a-z]/.test(pw) },
    { label: "Contains number", check: (pw) => /[0-9]/.test(pw) },
    {
      label: "Contains special character",
      check: (pw) => /[!@#$%^&*(),.?":{}|<>]/.test(pw),
    },
  ];

  const strengthMeta = (() => {
    const passed = passwordRules.filter((r) => r.check(p)).length;
    let level = 0;
    if (passed <= 2) level = 0;
    else if (passed <= 3) level = 1;
    else if (passed <= 4) level = 2;
    else level = 3;
    const meta = [
      {
        text: "Weak",
        textClass: "text-red-600",
        bars: ["bg-red-500", "bg-gray-200", "bg-gray-200", "bg-gray-200"],
      },
      {
        text: "Medium",
        textClass: "text-yellow-600",
        bars: ["bg-yellow-500", "bg-yellow-500", "bg-gray-200", "bg-gray-200"],
      },
      {
        text: "Strong",
        textClass: "text-blue-600",
        bars: ["bg-blue-500", "bg-blue-500", "bg-blue-500", "bg-gray-200"],
      },
      {
        text: "Very Strong",
        textClass: "text-green-600",
        bars: ["bg-green-500", "bg-green-500", "bg-green-500", "bg-green-500"],
      },
    ];
    return { level, ...meta[level] };
  })();

  async function sub(e) {
    e.preventDefault();
    if (!userId && !correlationId) {
      showToast(
        "Missing verification data. Please request OTP again.",
        "error"
      );
      setTimeout(() => nav("/forgot-password"), 2000);
      return;
    }
    if (p !== c) {
      showToast("Passwords do not match. Please check again.", "error");
      return;
    }
    if (p.length < 8) {
      showToast("Password must be at least 8 characters long.", "error");
      return;
    }

    setL(true);
    try {
      const payload = { newPassword: String(p) };
      if (userId) payload.userId = String(userId);
      if (correlationId) {
        payload.correlationId = String(correlationId);
        payload.requestId = String(correlationId);
        payload.verificationId = String(correlationId);
      }

      await http.post("/auth/otp/reset", payload, {
        meta: { public: true },
        timeout: 20000,
      });

      setResetSuccess(true);
      setTimeout(() => {
        try {
          localStorage.removeItem("forgot_identifier");
          localStorage.removeItem("forgot_verify_response");
        } catch {
          /* empty */
        }
        nav("/login", { replace: true });
      }, 2000);
    } catch (err) {
      const status = err?.response?.status;
      const body = err?.response?.data || {};
      const code = body.error || body.message || body.code || null;

      let msg;
      if (status === 400 && code === "not_verified_or_invalid") {
        msg = "Invalid request or OTP not verified. Please request a new OTP.";
        setTimeout(() => nav("/forgot-password"), 2000);
      } else if (status === 410 || code === "expired") {
        msg = "OTP has expired. Please request a new one.";
        setTimeout(() => nav("/forgot-password"), 2000);
      } else if (status === 401) {
        msg = "Unauthorized request. Please log in again.";
        setTimeout(() => nav("/login"), 2000);
      } else {
        msg = code || err?.message || "Unknown error. Please try again.";
      }

      showToast(msg, "error");
    } finally {
      setL(false);
    }
  }

  const getToastIcon = (type) => {
    switch (type) {
      case "success":
        return <CheckCircle className="w-5 h-5 text-green-500" />;
      case "error":
        return <XCircle className="w-5 h-5 text-red-500" />;
      case "warning":
        return <AlertCircle className="w-5 h-5 text-yellow-500" />;
      default:
        return <CheckCircle className="w-5 h-5 text-blue-500" />;
    }
  };

  const getToastBg = (type) => {
    switch (type) {
      case "success":
        return "bg-green-50 border-green-200";
      case "error":
        return "bg-red-50 border-red-200";
      case "warning":
        return "bg-yellow-50 border-yellow-200";
      default:
        return "bg-blue-50 border-blue-200";
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-indigo-50 via-purple-50 to-pink-50 flex items-center justify-center p-4 overflow-hidden">
      {toast && (
        <div
          className={`fixed top-4 right-4 z-50 flex items-center gap-3 px-4 py-3 rounded-lg border shadow-lg animate-toast-in ${getToastBg(
            toast.type
          )}`}
          style={{ minWidth: "300px", maxWidth: "500px" }}
        >
          {getToastIcon(toast.type)}
          <span className="flex-1 text-sm font-medium text-gray-800">
            {toast.message}
          </span>
          <button
            onClick={() => setToast(null)}
            className="text-gray-400 hover:text-gray-600 transition-colors"
          >
            <X className="w-4 h-4" />
          </button>
        </div>
      )}

      {resetSuccess && (
        <div className="fixed inset-0 bg-gradient-to-br from-indigo-600 to-purple-500 z-50 flex items-center justify-center animate-fade-in">
          <div className="text-center animate-scale-in">
            <div className="w-24 h-24 bg-white rounded-full flex items-center justify-center mb-6 mx-auto animate-bounce-once">
              <svg
                className="w-12 h-12 text-indigo-500"
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
            <h2 className="text-4xl font-bold text-white mb-2">
              Password reset successful!
            </h2>
            <p className="text-indigo-100 text-lg">
              Redirecting to login page...
            </p>
          </div>
        </div>
      )}

      <div className="w-full max-w-6xl flex gap-8 items-center">
        <div className="flex-1 flex flex-col justify-center animate-slide-in-left">
          <div className="mb-8">
            <div
              className="flex items-center gap-2 mb-8 animate-bounce-in"
              style={{ animationDelay: "0.2s" }}
            >
              <div className="w-8 h-8 bg-gradient-to-br from-indigo-600 to-purple-500 rounded-lg flex items-center justify-center">
                <div className="text-white text-xl font-bold">+</div>
              </div>
              <span className="text-gray-800 font-semibold text-lg">
                F-Laboratory Cloud
              </span>
            </div>

            <h1
              className="text-5xl font-bold mb-6 animate-fade-in"
              style={{ animationDelay: "0.3s" }}
            >
              <span className="text-transparent bg-clip-text bg-gradient-to-r from-indigo-500 via-purple-500 to-pink-500 inline-block">
                {displayText}
                <span className="animate-blink">|</span>
              </span>
            </h1>

            <p
              className="text-gray-600 mb-8 text-lg animate-fade-in"
              style={{ animationDelay: "0.5s" }}
            >
              Create a new password for your account. Choose a strong but
              memorable password to secure your account.
            </p>

            <div
              className="space-y-3 mb-8 animate-fade-in"
              style={{ animationDelay: "0.6s" }}
            >
              <h3 className="font-semibold text-gray-800 mb-3">
                Password requirements:
              </h3>
              {passwordRules.map((rule, index) => {
                const ok = p && rule.check(p);
                return (
                  <div
                    key={index}
                    className="flex items-center gap-3 animate-slide-in-left"
                    style={{ animationDelay: `${0.7 + index * 0.1}s` }}
                  >
                    <div
                      className={`w-5 h-5 rounded-full flex items-center justify-center transition-all ${
                        ok ? "bg-green-500" : "border-2 border-gray-300"
                      }`}
                    >
                      {ok && <Check className="w-3 h-3 text-white" />}
                    </div>
                    <span
                      className={
                        ok ? "text-green-600 font-medium" : "text-gray-600"
                      }
                    >
                      {rule.label}
                    </span>
                  </div>
                );
              })}
            </div>
          </div>

          <div
            className="bg-white rounded-2xl shadow-lg p-6 max-w-md animate-float"
            style={{ animationDelay: "1s" }}
          >
            <div className="flex items-center gap-4">
              <div className="w-16 h-16 bg-gradient-to-br from-indigo-500 to-purple-500 rounded-xl flex items-center justify-center animate-pulse">
                <Shield className="w-8 h-8 text-white" />
              </div>
              <div className="flex-1">
                <h3 className="font-bold text-gray-800 mb-1">
                  Maximum Security
                </h3>
                <p className="text-sm text-gray-600">
                  Your password is end-to-end encrypted and cannot be accessed
                  by anyone.
                </p>
              </div>
            </div>
          </div>
        </div>

        <div className="w-full max-w-md">
          <div
            className="bg-white rounded-3xl shadow-2xl p-8 animate-pop-in"
            style={{ animationDelay: "0.4s" }}
          >
            <div className="mb-6">
              <div className="w-16 h-16 bg-gradient-to-br from-indigo-100 to-purple-100 rounded-2xl flex items-center justify-center mb-4 animate-bounce-in">
                <Lock className="w-8 h-8 text-indigo-600" />
              </div>
              <h3 className="text-2xl font-bold text-gray-800 mb-2">
                {t("auth.reset_password")}
              </h3>
              <p className="text-gray-600 text-sm">
                Your new password must be different from the one previously
                used.
              </p>
            </div>

            <form onSubmit={sub} className="space-y-5">
              <div className="transform transition-all duration-300 hover:translate-x-1">
                <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                  <Lock className="w-4 h-4" />
                  {t("auth.new_password")}
                </label>
                <div className="relative">
                  <input
                    type={showPassword ? "text" : "password"}
                    value={p}
                    onChange={(e) => setP(e.target.value)}
                    placeholder="Enter your new password"
                    required
                    className="w-full px-4 py-3 pr-12 border-2 border-gray-300 rounded-xl focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 transition-all"
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword((v) => !v)}
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

              <div className="transform transition-all duration-300 hover:translate-x-1">
                <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                  <Lock className="w-4 h-4" />
                  Confirm password
                </label>
                <div className="relative">
                  <input
                    type={showConfirmPassword ? "text" : "password"}
                    value={c}
                    onChange={(e) => setC(e.target.value)}
                    placeholder="Confirm your new password"
                    required
                    className="w-full px-4 py-3 pr-12 border-2 border-gray-300 rounded-xl focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 transition-all"
                  />
                  <button
                    type="button"
                    onClick={() => setShowConfirmPassword((v) => !v)}
                    className="absolute right-4 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600 transition-colors"
                  >
                    {showConfirmPassword ? (
                      <EyeOff className="w-5 h-5" />
                    ) : (
                      <Eye className="w-5 h-5" />
                    )}
                  </button>
                </div>
              </div>

              {p && (
                <div className="animate-fade-in">
                  <div className="flex gap-1 mb-2">
                    {strengthMeta.bars.map((cls, i) => (
                      <div
                        key={i}
                        className={`h-2 flex-1 rounded-full transition-all ${cls}`}
                      />
                    ))}
                  </div>
                  <p
                    className={`text-sm font-medium ${strengthMeta.textClass}`}
                  >
                    Strength: {strengthMeta.text}
                  </p>
                </div>
              )}

              {c && (
                <div className="animate-fade-in">
                  {p === c ? (
                    <div className="flex items-center gap-2 text-green-600 text-sm">
                      <Check className="w-4 h-4" />
                      <span>Passwords match</span>
                    </div>
                  ) : (
                    <div className="flex items-center gap-2 text-red-600 text-sm">
                      <X className="w-4 h-4" />
                      <span>Passwords do not match</span>
                    </div>
                  )}
                </div>
              )}

              <button
                type="submit"
                disabled={l || !p || !c || p !== c}
                className="w-full py-3.5 bg-gradient-to-r from-indigo-500 to-purple-500 text-white font-semibold rounded-xl hover:shadow-lg hover:shadow-indigo-300 transition-all transform hover:scale-105 active:scale-95 disabled:opacity-50 disabled:cursor-not-allowed disabled:transform-none"
              >
                {l ? <Loading size={22} /> : t("auth.reset_password")}
              </button>
            </form>

            <div className="mt-6 text-center">
              <p className="text-sm text-gray-600">
                Remember your password?{" "}
                <button
                  onClick={() => nav("/login")}
                  className="text-indigo-600 hover:text-indigo-700 font-medium transition-colors hover:underline"
                >
                  Log in
                </button>
              </p>
            </div>
          </div>

          <div
            className="mt-6 text-center text-xs text-gray-500 animate-fade-in"
            style={{ animationDelay: "1.2s" }}
          >
            © 2025 F-Laboratory Cloud — Security • Terms • Support
          </div>
        </div>
      </div>

      <style>{`
        @keyframes slide-in-left { from { opacity: 0; transform: translateX(-50px); } to { opacity: 1; transform: translateX(0); } }
        @keyframes pop-in { 0% { opacity: 0; transform: scale(0.8) translateY(20px); } 50% { transform: scale(1.05); } 100% { opacity: 1; transform: scale(1) translateY(0); } }
        @keyframes fade-in { from { opacity: 0; } to { opacity: 1; } }
        @keyframes float { 0%, 100% { transform: translateY(0); } 50% { transform: translateY(-10px); } }
        @keyframes blink { 0%, 100% { opacity: 1; } 50% { opacity: 0; } }
        @keyframes toast-in { from { transform: translateX(100%); opacity: 0; } to { transform: translateX(0); opacity: 1; } }
        @keyframes scale-in { from { transform: scale(0); } to { transform: scale(1); } }
        @keyframes bounce-once { 0%,100% { transform: translateY(0); } 25% { transform: translateY(-20px); } 50% { transform: translateY(0); } 75% { transform: translateY(-10px); } }
        .animate-slide-in-left { animation: slide-in-left 0.6s ease-out forwards; opacity: 0; }
        .animate-pop-in { animation: pop-in 0.6s cubic-bezier(0.175,0.885,0.32,1.275) forwards; opacity: 0; }
        .animate-fade-in { animation: fade-in 0.6s ease-out forwards; opacity: 0; }
        .animate-float { animation: float 3s ease-in-out infinite; }
        .animate-blink { animation: blink 1s step-end infinite; }
        .animate-toast-in { animation: toast-in 0.3s ease-out; }
        .animate-scale-in { animation: scale-in .5s cubic-bezier(.175,.885,.32,1.275); }
        .animate-bounce-once { animation: bounce-once 1s ease; }
      `}</style>
    </div>
  );
}

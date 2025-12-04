import React, { useEffect, useState } from "react";
import { useNavigate, useLocation, useParams } from "react-router-dom";
import {
  Mail,
  ArrowLeft,
  Shield,
  Check,
  RefreshCw,
  CheckCircle,
  XCircle,
  AlertCircle,
  X,
  Clock,
} from "lucide-react";
import http from "../lib/api";
import Loading from "../components/Loading";
import { useTranslation } from "react-i18next";

export default function ForgotVerify() {
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

  const [identifier, setIdentifier] = useState(storedIdentifier);
  const [code, setCode] = useState("");
  const [l, setL] = useState(false);
  const [resending, setResending] = useState(false);
  const [toast, setToast] = useState(null);
  const [timeLeft, setTimeLeft] = useState(600); // 10 minutes in seconds
  const [displayText, setDisplayText] = useState("");
  const [currentTextIndex, setCurrentTextIndex] = useState(0);
  const fullText = "Verify OTP Code";

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

      const sentAt = loc.state.identifier.sentAt;
      if (sentAt) {
        const elapsed = Math.floor((Date.now() - sentAt) / 1000);
        setTimeLeft(Math.max(0, 600 - elapsed));
      } else {
        setTimeLeft(600);
      }
    }
  }, [loc.state]);

  useEffect(() => {
    if (timeLeft <= 0) return;

    const timer = setInterval(() => {
      setTimeLeft((prev) => {
        if (prev <= 1) {
          showToast("OTP has expired. Please request a new one.", "warning");
          return 0;
        }
        return prev - 1;
      });
    }, 1000);

    return () => clearInterval(timer);
  }, [timeLeft]);

  useEffect(() => {
    if (toast) {
      const timer = setTimeout(() => {
        setToast(null);
      }, 4000);
      return () => clearTimeout(timer);
    }
  }, [toast]);

  useEffect(() => {
    if (currentTextIndex < fullText.length) {
      const tId = setTimeout(() => {
        setDisplayText((p) => p + fullText[currentTextIndex]);
        setCurrentTextIndex((p) => p + 1);
      }, 60);
      return () => clearTimeout(tId);
    }
  }, [currentTextIndex]);

  const showToast = (message, type = "success") => {
    setToast({ message, type });
  };

  function parseIdentifier(idOrObj) {
    if (!idOrObj)
      return { userId: null, correlationId: null, identifier: null };
    if (typeof idOrObj === "object") {
      return {
        userId: idOrObj.userId || idOrObj.user_id || null,
        correlationId:
          idOrObj.correlationId ||
          idOrObj.correlation_id ||
          idOrObj.requestId ||
          idOrObj.correlation ||
          null,
        identifier: idOrObj.identifier || null,
      };
    }
    if (typeof idOrObj === "string") {
      try {
        const parsed = JSON.parse(idOrObj);
        if (typeof parsed === "object") {
          return {
            userId: parsed.userId || parsed.user_id || null,
            correlationId:
              parsed.correlationId ||
              parsed.correlation_id ||
              parsed.requestId ||
              parsed.correlation ||
              null,
            identifier: parsed.identifier || null,
          };
        }
      } catch {
        /* empty */
      }
      return { userId: null, correlationId: idOrObj, identifier: null };
    }
    return { userId: null, correlationId: null, identifier: null };
  }

  const {
    userId: idFromStore,
    correlationId: corrFromStore,
    identifier: emailFromStore,
  } = parseIdentifier(identifier);
  const routeParamId = params?.requestId || null;
  const userId = idFromStore || null;
  const correlationId = corrFromStore || routeParamId || null;

  async function resendOTP() {
    const emailOrUsername = emailFromStore || identifier?.identifier;

    if (!emailOrUsername) {
      showToast(
        "Email/username not found. Please go back and try again.",
        "error"
      );
      setTimeout(() => clearForResendAndNavigate(), 2000);
      return;
    }

    setResending(true);
    try {
      const res = await http.post(
        "/auth/otp/send",
        { usernameOrEmail: emailOrUsername },
        {
          meta: {
            public: true,
            requireCaptcha: true,
            action: import.meta.env.VITE_RECAPTCHA_ACTION_FORGOT_PASSWORD,
          },
        }
      );

      const data = res?.data || {};
      const newCorrelationId =
        data.correlationId ||
        data.requestId ||
        res?.headers?.["x-correlation-id"] ||
        null;

      const identObj = {
        userId: data.userId || userId || null,
        correlationId: newCorrelationId || correlationId,
        identifier: emailOrUsername,
        sentAt: Date.now(),
      };

      try {
        localStorage.setItem("forgot_identifier", JSON.stringify(identObj));
      } catch (err) {
        console.warn("[Resend OTP] localStorage.setItem failed", err);
      }

      setIdentifier(identObj);
      setCode("");
      setTimeLeft(600);
      showToast("A new OTP code has been sent to your email!", "success");
    } catch (err) {
      console.error("[Resend OTP error]", err);

      const resp = err?.response?.data || {};
      const serverCode = resp.code || resp.error || resp.message;

      let msg;
      if (
        err?.response?.status === 400 &&
        serverCode === "not_found_or_rate_limited"
      ) {
        msg = "OTP sending limit exceeded. Please try again later.";
      } else {
        msg = "Failed to resend OTP. Please try again.";
      }

      showToast(msg, "error");
    } finally {
      setResending(false);
    }
  }

  async function verify(e) {
    e.preventDefault();

    if (timeLeft <= 0) {
      showToast("OTP has expired. Please request a new one.", "error");
      return;
    }

    if (!correlationId) {
      showToast("Missing information. Please request OTP again.", "error");
      setTimeout(() => clearForResendAndNavigate(), 2000);
      return;
    }
    if (!code || String(code).trim().length === 0) {
      showToast("Please enter the OTP code.", "error");
      return;
    }

    setL(true);
    try {
      const res = await http.post(
        "/auth/otp/verify",
        {
          correlationId: String(correlationId),
          userId: userId ? String(userId) : undefined,
          otp: String(code).trim(),
        },
        { meta: { public: true }, timeout: 20000 }
      );

      const resp = res?.data || {};
      try {
        localStorage.setItem("forgot_verify_response", JSON.stringify(resp));
        localStorage.setItem(
          "forgot_identifier",
          JSON.stringify({
            userId: userId || null,
            correlationId:
              resp?.correlationId ||
              resp?.requestId ||
              resp?.verificationId ||
              correlationId,
          })
        );
      } catch {
        /* empty */
      }

      const token =
        resp?.verificationId ||
        resp?.requestId ||
        resp?.correlationId ||
        resp?.token ||
        correlationId;

      showToast("Verification successful! Redirecting...", "success");

      setTimeout(() => {
        nav(`/reset-password/${token}`, {
          state: {
            identifier: { userId: userId || null, correlationId: token },
            rawVerifyResponse: resp,
          },
        });
      }, 1500);
    } catch (err) {
      const status = err?.response?.status;
      const body = err?.response?.data || {};
      const codeErr = body.code || body.error || body.message || null;

      if (status === 400 && codeErr === "invalid_otp") {
        showToast("Invalid OTP code. Please try again.", "error");
      } else if (status === 410 || codeErr === "expired") {
        showToast("OTP has expired. Please request a new one.", "error");
        setTimeLeft(0);
      } else {
        const msg = codeErr || "Unknown error";
        showToast(msg, "error");
      }
    } finally {
      setL(false);
    }
  }

  function clearForResendAndNavigate() {
    try {
      localStorage.removeItem("forgot_identifier");
      localStorage.removeItem("forgot_verify_response");
    } catch {
      /* empty */
    }
    nav("/forgot-password", { replace: true });
  }

  const formatTime = (seconds) => {
    const mins = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${mins}:${secs.toString().padStart(2, "0")}`;
  };

  const getTimerColor = () => {
    if (timeLeft > 300) return "text-green-600";
    if (timeLeft > 120) return "text-yellow-600";
    return "text-red-600";
  };

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
    <div className="min-h-screen bg-gradient-to-br from-purple-50 via-pink-50 to-blue-50 flex items-center justify-center p-4 overflow-hidden">
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

      <div className="w-full max-w-6xl flex gap-8">
        <div className="flex-1 flex flex-col justify-center animate-slide-in-left">
          <div className="mb-8">
            <div
              className="flex items-center gap-2 mb-8 animate-bounce-in"
              style={{ animationDelay: "0.2s" }}
            >
              <div className="w-8 h-8 bg-gradient-to-br from-purple-600 to-blue-500 rounded-lg flex items-center justify-center">
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
              <span className="text-transparent bg-clip-text bg-gradient-to-r from-purple-500 via-pink-500 to-blue-500 inline-block">
                {displayText}
                <span className="animate-blink">|</span>
              </span>
            </h1>

            <p
              className="text-gray-600 mb-8 text-lg animate-fade-in"
              style={{ animationDelay: "0.5s" }}
            >
              Enter the OTP sent to your email.
            </p>

            <div className="space-y-4 text-gray-700">
              {[
                { icon: "📧", text: "Receive OTP via email", delay: "0.6s" },
                { icon: "🔒", text: "High security", delay: "0.7s" },
                { icon: "⚡", text: "Fast processing", delay: "0.8s" },
                { icon: "✨", text: "Simple & easy", delay: "0.9s" },
              ].map((item, index) => (
                <div
                  key={index}
                  className="flex items-center gap-3 animate-slide-in-left"
                  style={{ animationDelay: item.delay }}
                >
                  <div className="w-10 h-10 rounded-full bg-gradient-to-br from-purple-100 to-blue-100 flex items-center justify-center text-xl">
                    {item.icon}
                  </div>
                  <span>{item.text}</span>
                </div>
              ))}
            </div>
          </div>

          <div
            className="bg-white rounded-2xl shadow-lg p-6 max-w-md animate-float"
            style={{ animationDelay: "1s" }}
          >
            <div className="flex items-center gap-4">
              <div className="w-16 h-16 bg-gradient-to-br from-purple-500 to-blue-500 rounded-xl flex items-center justify-center animate-pulse">
                <Shield className="w-8 h-8 text-white" />
              </div>
              <div className="flex-1">
                <h3 className="font-bold text-gray-800 mb-1">High Security</h3>
                <p className="text-sm text-gray-600">
                  OTP is valid for 10 minutes and can be used only once.
                </p>
              </div>
            </div>
            <div className="mt-4 flex gap-2">
              {Array.from({ length: 4 }).map((_, i) => (
                <div
                  key={i}
                  className="h-1 flex-1 bg-gradient-to-r from-purple-400 to-blue-400 rounded-full animate-pulse"
                  style={{ animationDelay: `${i * 0.2}s` }}
                />
              ))}
            </div>
          </div>
        </div>

        <div
          className="w-full max-w-md animate-pop-in"
          style={{ animationDelay: "0.4s" }}
        >
          <div className="bg-white rounded-3xl shadow-xl p-8 transform transition-all duration-300 hover:shadow-2xl">
            <button
              type="button"
              onClick={() => nav("/login")}
              className="flex items-center gap-2 text-gray-600 hover:text-gray-800 mb-6 transition-all transform hover:-translate-x-1"
              disabled={l || resending}
            >
              <ArrowLeft className="w-4 h-4" />
              <span className="text-sm font-medium">Back to login</span>
            </button>

            <div className="mb-6">
              <div className="w-16 h-16 bg-gradient-to-br from-purple-100 to-blue-100 rounded-2xl flex items-center justify-center mb-4 animate-bounce-in">
                <Mail className="w-8 h-8 text-purple-600" />
              </div>
              <h3 className="text-2xl font-bold text-gray-800 mb-2">
                {t("Verify OTP") || "Verify OTP"}
              </h3>
              <p className="text-gray-600 text-sm">
                We have sent an OTP to your email. Enter the code to continue.
              </p>
            </div>

            <div className="mb-4 p-4 bg-gradient-to-r from-purple-50 to-blue-50 rounded-lg border border-purple-100">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <Clock className="w-5 h-5 text-purple-600" />
                  <span className="text-sm font-medium text-gray-700">
                    Time remaining
                  </span>
                </div>
                <span
                  className={`text-2xl font-bold ${getTimerColor()} transition-colors`}
                >
                  {formatTime(timeLeft)}
                </span>
              </div>
              {timeLeft <= 0 && (
                <p className="text-xs text-red-600 mt-2">
                  OTP has expired. Please request a new code.
                </p>
              )}
            </div>

            <form onSubmit={verify} className="space-y-4">
              <div className="transform transition-all duration-300 hover:translate-x-1">
                <label className="flex items-center gap-2 text-sm text-gray-600 mb-2">
                  <Mail className="w-4 h-4" />
                  {t("OTP Code") || "OTP Code"}
                </label>
                <input
                  type="text"
                  value={code}
                  onChange={(e) => setCode(e.target.value)}
                  placeholder="Enter OTP code"
                  required
                  className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-purple-500 focus:border-transparent transition-all"
                  disabled={l || resending || timeLeft <= 0}
                />
              </div>

              <button
                type="submit"
                disabled={l || resending || timeLeft <= 0}
                className="w-full py-3 bg-gradient-to-r from-purple-500 to-blue-500 text-white font-semibold rounded-lg hover:shadow-lg transition-all transform hover:scale-105 active:scale-95 disabled:opacity-70"
              >
                {l ? (
                  <Loading size={22} />
                ) : (
                  <span className="flex items-center justify-center gap-2">
                    <Check className="w-5 h-5" />
                    {t("Verify") || "Verify"}
                  </span>
                )}
              </button>
            </form>

            <div className="mt-6 text-center">
              <p className="text-sm text-gray-600">
                Didn’t receive the code?{" "}
                <button
                  type="button"
                  onClick={resendOTP}
                  disabled={l || resending}
                  className="text-purple-600 hover:text-purple-700 font-medium hover:underline disabled:opacity-50 inline-flex items-center gap-1"
                >
                  {resending ? (
                    <>
                      <RefreshCw className="w-3 h-3 animate-spin" />
                      Sending...
                    </>
                  ) : (
                    "Resend OTP"
                  )}
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
        @keyframes bounce-in { 0% { opacity: 0; transform: scale(0.3); } 50% { transform: scale(1.1); } 100% { opacity: 1; transform: scale(1); } }
        @keyframes float { 0%,100% { transform: translateY(0); } 50% { transform: translateY(-10px); } }
        @keyframes blink { 0%,100% { opacity: 1; } 50% { opacity: 0; } }
        @keyframes toast-in { from { transform: translateX(100%); opacity: 0; } to { transform: translateX(0); opacity: 1; } }
        .animate-slide-in-left { animation: slide-in-left .6s ease-out forwards; opacity: 0; }
        .animate-pop-in { animation: pop-in .6s cubic-bezier(.175,.885,.32,1.275) forwards; opacity: 0; }
        .animate-fade-in { animation: fade-in .6s ease-out forwards; opacity: 0; }
        .animate-float { animation: float 3s ease-in-out infinite; }
        .animate-blink { animation: blink 1s step-end infinite; }
        .animate-toast-in { animation: toast-in 0.3s ease-out; }
      `}</style>
    </div>
  );
}

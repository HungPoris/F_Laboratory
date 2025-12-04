import React, { useState, useEffect } from "react";
import {
  Mail,
  ArrowLeft,
  Send,
  Shield,
  CheckCircle,
  XCircle,
  AlertCircle,
  X,
} from "lucide-react";
import { useNavigate } from "react-router-dom";
import http from "../lib/api";
import Loading from "../components/Loading";
import { useTranslation } from "react-i18next";

export default function ForgotSend() {
  // eslint-disable-next-line no-unused-vars
  const { t } = useTranslation();
  const nav = useNavigate();

  const [v, setV] = useState("");
  const [l, setL] = useState(false);
  const [toast, setToast] = useState(null);

  const [displayText, setDisplayText] = useState("");
  const [currentTextIndex, setCurrentTextIndex] = useState(0);
  const fullText = "Recover your account";

  useEffect(() => {
    if (currentTextIndex < fullText.length) {
      const tId = setTimeout(() => {
        setDisplayText((p) => p + fullText[currentTextIndex]);
        setCurrentTextIndex((p) => p + 1);
      }, 80);
      return () => clearTimeout(tId);
    }
  }, [currentTextIndex]);

  useEffect(() => {
    if (toast) {
      const timer = setTimeout(() => {
        setToast(null);
      }, 4000);
      return () => clearTimeout(timer);
    }
  }, [toast]);

  const showToast = (message, type = "success") => {
    setToast({ message, type });
  };

  async function send(e) {
    e.preventDefault();
    const identifier = String(v || "").trim();
    if (!identifier) {
      showToast("Please enter your email or username.", "error");
      return;
    }

    setL(true);
    try {
      console.debug("[OTP] send request", { identifier });

      const res = await http.post(
        "/auth/otp/send",
        { usernameOrEmail: identifier },
        {
          meta: { public: true },
        }
      );

      console.debug("[OTP] response", {
        status: res?.status,
        data: res?.data,
        headers: res?.headers,
      });

      const data = res?.data || {};
      const correlationId =
        data.correlationId ||
        data.requestId ||
        res?.headers?.["x-correlation-id"] ||
        res?.headers?.["x-request-id"] ||
        res?.headers?.["request-id"] ||
        null;

      const identObj = {
        userId: data.userId || null,
        correlationId,
        identifier,
        sentAt: Date.now(),
      };

      try {
        localStorage.setItem("forgot_identifier", JSON.stringify(identObj));
      } catch (err) {
        console.warn("[OTP] localStorage.setItem failed", err);
      }

      showToast(
        "OTP has been sent to your email! Please check your inbox.",
        "success"
      );

      setTimeout(() => {
        if (identObj.correlationId) {
          nav(`/verify-otp/${identObj.correlationId}`, {
            state: { identifier: identObj },
          });
        } else {
          nav("/verify-otp", { state: { identifier: identObj } });
        }
      }, 1500);
    } catch (err) {
      console.error(
        "[OTP send error]",
        err?.response?.status,
        err?.response?.data || err?.message
      );

      const resp = err?.response?.data || {};
      const serverCode = resp.code || resp.error || resp.message;

      let msg;
      if (
        err?.response?.status === 400 &&
        serverCode === "missing_username_or_email"
      ) {
        msg = "Please enter your email or username.";
      } else if (
        err?.response?.status === 400 &&
        (serverCode === "not_found_or_rate_limited" ||
          serverCode === "not_found")
      ) {
        msg =
          "User not found or request limit reached. Please try again later.";
      } else if (err?.response?.status === 401) {
        msg = "Unauthorized request.";
      } else if (!err?.response) {
        msg = "Unable to connect to the server. Please check your network.";
      } else {
        msg = "Failed to send OTP. Please try again.";
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
              Don’t worry! We’ll send you instructions to reset your password
              immediately.
            </p>

            <div className="space-y-4 text-gray-700">
              {[
                { icon: "📧", text: "Receive OTP via email", delay: "0.6s" },
                { icon: "🔒", text: "Strong security", delay: "0.7s" },
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
                  The OTP is valid for 10 minutes and can be used only once.
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
              disabled={l}
            >
              <ArrowLeft className="w-4 h-4" />
              <span className="text-sm font-medium">Back to login</span>
            </button>

            <div className="mb-6">
              <div className="w-16 h-16 bg-gradient-to-br from-purple-100 to-blue-100 rounded-2xl flex items-center justify-center mb-4 animate-bounce-in">
                <Mail className="w-8 h-8 text-purple-600" />
              </div>
              <h3 className="text-2xl font-bold text-gray-800 mb-2">
                Send OTP
              </h3>
              <p className="text-gray-600 text-sm">
                Enter your email or username, and we’ll send an OTP to reset
                your password.
              </p>
            </div>

            <form onSubmit={send} className="space-y-4">
              <div className="transform transition-all duration-300 hover:translate-x-1">
                <label className="flex items-center gap-2 text-sm text-gray-600 mb-2">
                  <Mail className="w-4 h-4" />
                  Email or Username
                </label>
                <input
                  type="text"
                  value={v}
                  onChange={(e) => setV(e.target.value)}
                  placeholder="you@example.com or username"
                  required
                  className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-purple-500 focus:border-transparent transition-all"
                  disabled={l}
                  aria-label="usernameOrEmail"
                />
              </div>

              <button
                type="submit"
                disabled={l}
                className="w-full py-3 bg-gradient-to-r from-purple-500 to-blue-500 text-white font-semibold rounded-lg hover:shadow-lg hover:shadow-purple-200 transition-all transform hover:scale-105 active:scale-95 disabled:opacity-70"
              >
                {l ? (
                  <Loading size={22} />
                ) : (
                  <span className="flex items-center justify-center gap-2">
                    <Send className="w-5 h-5" />
                    Send OTP
                  </span>
                )}
              </button>
            </form>

            <div className="mt-8 bg-gradient-to-r from-purple-50 to-blue-50 rounded-lg p-4 border border-purple-100">
              <div className="flex gap-3">
                <div className="text-2xl">💡</div>
                <div>
                  <h4 className="font-semibold text-gray-800 text-sm mb-1">
                    Helpful Tip
                  </h4>
                  <p className="text-xs text-gray-600">
                    Check your Spam or Junk folder if you don’t see the email.
                    The OTP is valid for 10 minutes.
                  </p>
                </div>
              </div>
            </div>

            <div className="mt-6 text-center">
              <p className="text-sm text-gray-600">
                Remember your password?{" "}
                <button
                  type="button"
                  onClick={() => nav("/login")}
                  className="text-purple-600 hover:text-purple-700 font-medium hover:underline"
                  disabled={l}
                >
                  Log in now
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
        .animate-bounce-in { animation: bounce-in .6s ease-out forwards; opacity: 0; }
        .animate-float { animation: float 3s ease-in-out infinite; }
        .animate-blink { animation: blink 1s step-end infinite; }
        .animate-toast-in { animation: toast-in 0.3s ease-out; }
      `}</style>
    </div>
  );
}

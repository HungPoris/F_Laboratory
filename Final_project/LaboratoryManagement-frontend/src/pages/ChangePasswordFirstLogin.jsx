import React, { useState, useEffect, useRef } from "react";
import {
  Eye,
  EyeOff,
  Lock,
  Shield,
  Key,
  CheckCircle,
  AlertCircle,
} from "lucide-react";
import { useNavigate, useLocation } from "react-router-dom";
import http from "../lib/api";
import * as notify from "../lib/notify";
import { clearSession } from "../lib/auth";
import { getLoginPath, setLoginType } from "../lib/loginRedirect";
import { useTranslation } from "react-i18next";

export default function ChangePasswordFirstLogin() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const location = useLocation();

  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [showCurrentPassword, setShowCurrentPassword] = useState(false);
  const [showNewPassword, setShowNewPassword] = useState(false);
  const [showConfirmPassword, setShowConfirmPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [changeSuccess, setChangeSuccess] = useState(false);
  const [formError, setFormError] = useState(null);

  const [displayText, setDisplayText] = useState("");
  const [currentTextIndex, setCurrentTextIndex] = useState(0);
  const fullText = "secure your account";

  const isSubmittingRef = useRef(false);

  const [passwordStrength, setPasswordStrength] = useState({
    hasMinLength: false,
    hasUppercase: false,
    hasLowercase: false,
    hasNumber: false,
    hasSpecial: false,
  });

  useEffect(() => {
    const handleBeforeUnload = (e) => {
      e.preventDefault();
      e.returnValue = "";
    };
    window.addEventListener("beforeunload", handleBeforeUnload);
    return () => {
      window.removeEventListener("beforeunload", handleBeforeUnload);
    };
  }, []);

  useEffect(() => {
    if (!location.state?.isFirstLogin) {
      notify.warn("Please login first");
      const loginPath = getLoginPath();
      navigate(loginPath, { replace: true });
    } else {
      // Lưu loại login từ state nếu có
      if (location.state?.loginType) {
        setLoginType(location.state.loginType);
      }
    }
  }, [location, navigate]);

  useEffect(() => {
    if (currentTextIndex < fullText.length) {
      const tmo = setTimeout(() => {
        setDisplayText((prev) => prev + fullText[currentTextIndex]);
        setCurrentTextIndex((prev) => prev + 1);
      }, 100);
      return () => clearTimeout(tmo);
    }
  }, [currentTextIndex]);

  useEffect(() => {
    if (newPassword) {
      setPasswordStrength({
        hasMinLength: newPassword.length >= 8,
        hasUppercase: /[A-Z]/.test(newPassword),
        hasLowercase: /[a-z]/.test(newPassword),
        hasNumber: /[0-9]/.test(newPassword),
        hasSpecial: /[!@#$%^&*(),.?":{}|<>]/.test(newPassword),
      });
    } else {
      setPasswordStrength({
        hasMinLength: false,
        hasUppercase: false,
        hasLowercase: false,
        hasNumber: false,
        hasSpecial: false,
      });
    }
  }, [newPassword]);

  function resolveErrorMessage(responseData, httpStatus = null) {
    if (!responseData || typeof responseData !== "object") {
      if (httpStatus === 401)
        return t("errors.UNAUTHORIZED", { defaultValue: "Unauthorized" });
      if (httpStatus === 403)
        return t("errors.FORBIDDEN", { defaultValue: "Forbidden" });
      if (httpStatus === 500)
        return t("errors.UNKNOWN_ERROR", { defaultValue: "Unknown error" });
      return t("errors.UNKNOWN_ERROR", { defaultValue: "Unknown error" });
    }

    if (responseData.message && typeof responseData.message === "string") {
      const rawMsg = responseData.message.trim();
      if (
        rawMsg &&
        !/^[A-Z0-9_]+$/.test(rawMsg) &&
        !/^[a-z0-9_]+$/.test(rawMsg)
      ) {
        return rawMsg;
      }
    }

    let code =
      responseData.error || responseData.code || responseData.message || null;

    if (
      !code &&
      responseData.errors &&
      typeof responseData.errors === "object"
    ) {
      try {
        const arr = Object.values(responseData.errors).flat();
        if (arr.length) code = arr[0];
      } catch { /* empty */ }
    }

    if (code) {
      const norm = String(code).trim().toUpperCase();
      const msg = t(`errors.${norm}`, { defaultValue: "" });
      if (msg && msg !== `errors.${norm}`) return msg;
    }

    if (httpStatus === 401)
      return t("errors.UNAUTHORIZED", { defaultValue: "Unauthorized" });
    if (httpStatus === 403)
      return t("errors.FORBIDDEN", { defaultValue: "Forbidden" });
    return t("errors.UNKNOWN_ERROR", { defaultValue: "Unknown error" });
  }

  const validatePassword = () => {
    if (!currentPassword) {
      return t("errors.PASSWORD_REQUIRED", {
        defaultValue: "Current password is required",
      });
    }
    if (!newPassword) {
      return t("errors.NEW_PASSWORD_REQUIRED", {
        defaultValue: "New password is required",
      });
    }
    if (!confirmPassword) {
      return t("errors.CONFIRM_PASSWORD_REQUIRED", {
        defaultValue: "Please confirm your new password",
      });
    }
    if (newPassword.length < 8) {
      return t("errors.PASSWORD_TOO_SHORT", {
        defaultValue: "Password must be at least 8 characters long",
      });
    }
    if (newPassword === currentPassword) {
      return t("errors.PASSWORD_SAME_AS_OLD", {
        defaultValue: "New password must be different from current password",
      });
    }
    if (newPassword !== confirmPassword) {
      return t("errors.PASSWORD_MISMATCH", {
        defaultValue: "Passwords do not match",
      });
    }
    if (
      !passwordStrength.hasUppercase ||
      !passwordStrength.hasLowercase ||
      !passwordStrength.hasNumber
    ) {
      return t("errors.WEAK_PASSWORD", {
        defaultValue: "Password must meet all security requirements",
      });
    }
    return null;
  };

  const handleSubmit = async () => {
    if (isSubmittingRef.current) return;

    const validationError = validatePassword();
    if (validationError) {
      setFormError(validationError);
      return;
    }

    setFormError(null);
    setLoading(true);
    isSubmittingRef.current = true;

    try {
      await http.post("/api/v1/profile/change-password-first-login", {
        currentPassword: currentPassword,
        newPassword: newPassword,
        confirmPassword: confirmPassword,
      });

      setChangeSuccess(true);

      notify.success(
        t("auth.first_login_password_changed", {
          defaultValue:
            "Password changed successfully! Please login with your new password.",
        })
      );

      clearSession();

      setTimeout(() => {
        const loginPath = getLoginPath();
        navigate(loginPath, { replace: true });
      }, 2000);
    } catch (err) {
      const msg =
        resolveErrorMessage(err?.response?.data, err?.response?.status) ||
        t("errors.UNKNOWN_ERROR", {
          defaultValue: "Failed to change password. Please try again.",
        });
      setFormError(msg);
      notify.error(msg);
    } finally {
      setLoading(false);
      isSubmittingRef.current = false;
    }
  };

  const handleKeyPress = (e) => {
    if (e.key === "Enter") {
      handleSubmit();
    }
  };

  const StrengthIndicator = ({ met, label }) => (
    <div className="flex items-center gap-2 text-xs">
      {met ? (
        <CheckCircle className="w-4 h-4 text-emerald-500" />
      ) : (
        <AlertCircle className="w-4 h-4 text-gray-300" />
      )}
      <span className={met ? "text-emerald-600" : "text-gray-400"}>
        {label}
      </span>
    </div>
  );

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 via-cyan-50 to-emerald-50 flex items-center justify-center px-4 py-6 md:py-10 overflow-hidden">
      {changeSuccess && (
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
            <h2 className="text-3xl md:text-4xl font-bold text-white mb-2">
              {t("auth.password_changed_success", {
                defaultValue: "Password Changed!",
              })}
            </h2>
            <p className="text-blue-100 text-base md:text-lg">
              {t("auth.redirecting_to_login", {
                defaultValue: "Redirecting to login...",
              })}
            </p>
          </div>
        </div>
      )}

      <div className="w-full max-w-[1200px] lg:grid lg:grid-cols-2 items-center gap-12">
        <div className="flex flex-col justify-center animate-slide-in-left">
          <div className="mb-8 md:mb-10">
            <div
              className="flex items-center gap-2 mb-6 md:mb-8 animate-bounce-in"
              style={{ animationDelay: "0.2s" }}
            >
              <div className="w-8 h-8 bg-gradient-to-br from-blue-600 to-cyan-500 rounded-lg flex items-center justify-center">
                <div className="text-white text-xl font-bold">+</div>
              </div>
              <span className="text-gray-800 font-semibold text-base md:text-lg">
                F-Laboratory Cloud
              </span>
            </div>
            <h1
              className="text-4xl md:text-5xl font-bold mb-3 md:mb-4 animate-fade-in"
              style={{ animationDelay: "0.3s" }}
            >
              {t("auth.first_time_here", { defaultValue: "First time here?" })}
            </h1>
            <h2 className="text-4xl md:text-5xl font-bold mb-5 md:mb-6">
              <span className="text-transparent bg-clip-text bg-gradient-to-r from-blue-500 via-cyan-500 to-emerald-500 inline-block">
                {displayText}
                <span className="animate-blink">|</span>
              </span>
            </h2>
            <p
              className="text-gray-600 mb-6 md:mb-8 text-base md:text-lg animate-fade-in"
              style={{ animationDelay: "0.5s" }}
            >
              {t("auth.first_login_description", {
                defaultValue:
                  "For security purposes, you must change your temporary password before accessing the system.",
              })}
            </p>
            <div className="space-y-3 text-gray-700">
              {[
                {
                  text: t("auth.tip_strong_password", {
                    defaultValue: "Create a strong, unique password",
                  }),
                  icon: Key,
                },
                {
                  text: t("auth.tip_meet_requirements", {
                    defaultValue: "Must meet all security requirements",
                  }),
                  icon: Shield,
                },
                {
                  text: t("auth.tip_different_password", {
                    defaultValue: "Different from your temporary password",
                  }),
                  icon: Lock,
                },
              ].map((item, i) => {
                const IconComponent = item.icon;
                return (
                  <div
                    key={i}
                    className="flex items-center gap-3 animate-slide-in-left"
                    style={{ animationDelay: `${0.6 + i * 0.1}s` }}
                  >
                    <div className="w-5 h-5 flex items-center justify-center">
                      <IconComponent className="w-5 h-5 text-emerald-500" />
                    </div>
                    <span>{item.text}</span>
                  </div>
                );
              })}
            </div>
          </div>

          <div
            className="bg-white rounded-2xl shadow-lg p-5 md:p-6 max-w-md animate-float"
            style={{ animationDelay: "0.9s" }}
          >
            <div className="flex gap-2 mb-4">
              <div className="w-3 h-3 rounded-full bg-red-400 animate-pulse" />
              <div className="w-3 h-3 rounded-full bg-yellow-400 animate-pulse" />
              <div className="w-3 h-3 rounded-full bg-green-400 animate-pulse" />
            </div>
            <div className="space-y-3">
              <div className="flex items-center gap-3 p-3 bg-gradient-to-r from-blue-50 to-cyan-50 rounded-lg">
                <Shield className="w-6 h-6 text-blue-500" />
                <div className="flex-1">
                  <div className="h-2 bg-gray-200 rounded-full w-full mb-2" />
                  <div className="h-2 bg-gray-200 rounded-full w-2/3" />
                </div>
              </div>
              <div className="flex items-center gap-3 p-3 bg-gradient-to-r from-emerald-50 to-green-50 rounded-lg">
                <Key className="w-6 h-6 text-emerald-500" />
                <div className="flex-1">
                  <div className="h-2 bg-gray-200 rounded-full w-full mb-2" />
                  <div className="h-2 bg-gray-200 rounded-full w-3/4" />
                </div>
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
                {t("auth.change_password_title", {
                  defaultValue: "Change Your Password",
                })}
              </h3>
              <p className="text-gray-500 text-sm">
                {t("auth.change_password_subtitle", {
                  defaultValue: "Create a new secure password for your account",
                })}
              </p>
            </div>

            <div className="space-y-5">
              <div className="transition-all duration-300 hover:translate-x-1">
                <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                  <Lock className="w-4 h-4" />
                  {t("profile.current_password", {
                    defaultValue: "Current Password",
                  })}
                </label>
                <div className="relative">
                  <input
                    type={showCurrentPassword ? "text" : "password"}
                    value={currentPassword}
                    onChange={(e) => setCurrentPassword(e.target.value)}
                    onKeyPress={handleKeyPress}
                    placeholder={t("auth.enter_temp_password", {
                      defaultValue: "Enter your current password",
                    })}
                    className="w-full px-4 py-3 pr-12 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all bg-slate-50"
                  />
                  <button
                    type="button"
                    onClick={() => setShowCurrentPassword(!showCurrentPassword)}
                    className="absolute right-4 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600 transition-colors"
                  >
                    {showCurrentPassword ? (
                      <EyeOff className="w-5 h-5" />
                    ) : (
                      <Eye className="w-5 h-5" />
                    )}
                  </button>
                </div>
              </div>

              <div className="transition-all duration-300 hover:translate-x-1">
                <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                  <Key className="w-4 h-4" />
                  {t("profile.new_password", { defaultValue: "New Password" })}
                </label>
                <div className="relative">
                  <input
                    type={showNewPassword ? "text" : "password"}
                    value={newPassword}
                    onChange={(e) => setNewPassword(e.target.value)}
                    onKeyPress={handleKeyPress}
                    placeholder={t("profile.new_password_placeholder", {
                      defaultValue: "Enter your new password",
                    })}
                    className="w-full px-4 py-3 pr-12 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all bg-slate-50"
                  />
                  <button
                    type="button"
                    onClick={() => setShowNewPassword(!showNewPassword)}
                    className="absolute right-4 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-600 transition-colors"
                  >
                    {showNewPassword ? (
                      <EyeOff className="w-5 h-5" />
                    ) : (
                      <Eye className="w-5 h-5" />
                    )}
                  </button>
                </div>
              </div>

              {newPassword && (
                <div className="p-4 bg-blue-50 rounded-lg border border-blue-100 space-y-2">
                  <p className="text-xs font-semibold text-gray-700 mb-2">
                    {t("profile.password_requirements", {
                      defaultValue: "Password Requirements:",
                    })}
                  </p>
                  <StrengthIndicator
                    met={passwordStrength.hasMinLength}
                    label={t("profile.req_length", {
                      defaultValue: "At least 8 characters",
                    })}
                  />
                  <StrengthIndicator
                    met={passwordStrength.hasUppercase}
                    label={t("profile.req_uppercase", {
                      defaultValue: "One uppercase letter (A-Z)",
                    })}
                  />
                  <StrengthIndicator
                    met={passwordStrength.hasLowercase}
                    label={t("profile.req_lowercase", {
                      defaultValue: "One lowercase letter (a-z)",
                    })}
                  />
                  <StrengthIndicator
                    met={passwordStrength.hasNumber}
                    label={t("profile.req_number", {
                      defaultValue: "One number (0-9)",
                    })}
                  />
                </div>
              )}

              <div className="transition-all duration-300 hover:translate-x-1">
                <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                  <Shield className="w-4 h-4" />
                  {t("profile.confirm_new_password", {
                    defaultValue: "Confirm New Password",
                  })}
                </label>
                <div className="relative">
                  <input
                    type={showConfirmPassword ? "text" : "password"}
                    value={confirmPassword}
                    onChange={(e) => setConfirmPassword(e.target.value)}
                    onKeyPress={handleKeyPress}
                    placeholder={t("profile.confirm_new_password_placeholder", {
                      defaultValue: "Confirm your new password",
                    })}
                    className="w-full px-4 py-3 pr-12 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent transition-all bg-slate-50"
                  />
                  <button
                    type="button"
                    onClick={() => setShowConfirmPassword(!showConfirmPassword)}
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

              {formError && (
                <div className="p-4 bg-red-50 border border-red-200 rounded-lg animate-fade-in">
                  <p className="text-sm text-red-600">{formError}</p>
                </div>
              )}

              <button
                onClick={handleSubmit}
                disabled={loading}
                className="w-full py-3.5 bg-gradient-to-r from-blue-500 to-emerald-500 text-white font-semibold rounded-lg hover:shadow-lg hover:shadow-blue-200 transition-all hover:scale-105 active:scale-95 disabled:opacity-70 disabled:cursor-not-allowed"
              >
                {loading ? (
                  <div className="flex items-center justify-center gap-2">
                    <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin" />
                    <span>
                      {t("common.processing", {
                        defaultValue: "Changing Password...",
                      })}
                    </span>
                  </div>
                ) : (
                  t("auth.set_new_password", {
                    defaultValue: "Change Password",
                  })
                )}
              </button>
            </div>

            <div className="mt-8 pt-6 border-t border-gray-200">
              <h4 className="text-sm font-semibold text-gray-700 mb-4 flex items-center gap-2">
                <Shield className="w-4 h-4 text-blue-600" />
                {t("auth.security_tips_title", {
                  defaultValue: "Password Security Tips",
                })}
              </h4>
              <div className="space-y-3">
                <div className="flex items-start gap-3 text-xs text-gray-600">
                  <Key className="w-4 h-4 text-emerald-500 mt-0.5 flex-shrink-0" />
                  <p>
                    {t("auth.tip_unique", {
                      defaultValue:
                        "Use a unique password that you don't use for other accounts.",
                    })}
                  </p>
                </div>
                <div className="flex items-start gap-3 text-xs text-gray-600">
                  <Shield className="w-4 h-4 text-emerald-500 mt-0.5 flex-shrink-0" />
                  <p>
                    {t("auth.tip_avoid_personal", {
                      defaultValue:
                        "Avoid using personal information like birthdays or names.",
                    })}
                  </p>
                </div>
                <div className="flex items-start gap-3 text-xs text-gray-600">
                  <Lock className="w-4 h-4 text-emerald-500 mt-0.5 flex-shrink-0" />
                  <p>
                    {t("auth.tip_password_manager", {
                      defaultValue:
                        "Consider using a password manager to generate and store passwords.",
                    })}
                  </p>
                </div>
              </div>
            </div>

            <div className="mt-6 p-4 bg-amber-50 rounded-lg border border-amber-200">
              <p className="text-xs text-amber-800 leading-relaxed">
                <strong>
                  {t("common.important", { defaultValue: "Important:" })}
                </strong>{" "}
                {t("auth.first_login_footer", {
                  defaultValue:
                    "After changing your password, you will be redirected to the login page. Please use your new password to sign in.",
                })}
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
        @keyframes scale-in { from { transform: scale(0); } to { transform: scale(1); } }
        @keyframes bounce-once { 0%,100% { transform: translateY(0); } 25% { transform: translateY(-20px); } 50% { transform: translateY(0); } 75% { transform: translateY(-10px); } }
        .animate-slide-in-left { animation: slide-in-left .6s ease-out forwards; opacity: 0; }
        .animate-pop-in { animation: pop-in .6s cubic-bezier(.175,.885,.32,1.275) forwards; opacity: 0; }
        .animate-fade-in { animation: fade-in .6s ease-out forwards; opacity: 0; }
        .animate-bounce-in { animation: bounce-in .6s ease-out forwards; opacity: 0; }
        .animate-float { animation: float 3s ease-in-out infinite; }
        .animate-blink { animation: blink 1s step-end infinite; }
        .animate-scale-in { animation: scale-in .5s cubic-bezier(.175,.885,.32,1.275); }
        .animate-bounce-once { animation: bounce-once 1s ease; }
      `}</style>
    </div>
  );
}

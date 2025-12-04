// src/pages/CommonPage/ChangePassword.jsx
import React, { useState, useMemo } from "react";
import {
  Lock,
  Eye,
  EyeOff,
  ShieldCheck,
  AlertCircle,
  CheckCircle2,
} from "lucide-react";
import http from "../../lib/api";
import * as notify from "../../lib/notify";
import { clearSession } from "../../lib/auth";
import { getLoginPath } from "../../lib/loginRedirect";
import { useTranslation } from "react-i18next";

export default function ChangePassword() {
  const { t } = useTranslation();

  const [form, setForm] = useState({
    currentPassword: "",
    newPassword: "",
    confirm: "",
  });
  const [saving, setSaving] = useState(false);
  const [showPassword, setShowPassword] = useState({
    current: false,
    new: false,
    confirm: false,
  });

  const [fieldErrors, setFieldErrors] = useState({
    currentPassword: null,
    newPassword: null,
    confirm: null,
  });
  const [serverError, setServerError] = useState(null);

  const onChange = (e) => {
    const { name, value } = e.target;
    setForm((s) => ({ ...s, [name]: value }));
    setFieldErrors((fe) => ({ ...fe, [name]: null }));
    setServerError(null);
  };

  const toggleShowPassword = (field) => {
    setShowPassword((s) => ({ ...s, [field]: !s[field] }));
  };

  function validateNewPassword(pw) {
    return {
      length: pw.length >= 8 && pw.length <= 128,
      uppercase: /[A-Z]/.test(pw),
      lowercase: /[a-z]/.test(pw),
      number: /[0-9]/.test(pw),
    };
  }

  const passwordChecks = useMemo(
    () => validateNewPassword(form.newPassword || ""),
    [form.newPassword]
  );
  const allChecksPassed = useMemo(
    () => Object.values(passwordChecks).every(Boolean),
    [passwordChecks]
  );

  function resolveErrorMessage(responseData, httpStatus = null) {
    if (!responseData || typeof responseData !== "object") {
      if (httpStatus === 401) return t("errors.UNAUTHORIZED");
      if (httpStatus === 403) return t("errors.FORBIDDEN");
      if (httpStatus === 500) return t("errors.UNKNOWN_ERROR");
      return t("errors.UNKNOWN_ERROR");
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
      } catch {
        /* ignore */
      }
    }

    if (code) {
      const norm = String(code).trim().toUpperCase();
      const msg = t(`errors.${norm}`, { defaultValue: "" });
      if (msg && msg !== `errors.${norm}`) return msg;
    }

    if (httpStatus === 401) return t("errors.UNAUTHORIZED");
    if (httpStatus === 403) return t("errors.FORBIDDEN");
    return t("errors.UNKNOWN_ERROR");
  }

  const onSubmit = async (e) => {
    e.preventDefault();

    setFieldErrors({ currentPassword: null, newPassword: null, confirm: null });
    setServerError(null);

    if (!form.currentPassword) {
      notify.error(t("errors.PASSWORD_REQUIRED"));
      return;
    }
    if (!allChecksPassed) {
      notify.error(t("errors.WEAK_PASSWORD"));
      return;
    }
    if (form.newPassword !== form.confirm) {
      notify.error(
        t("errors.PASSWORD_SAME_AS_OLD", {
          defaultValue: "Passwords do not match.",
        })
      );
      return;
    }

    setSaving(true);
    try {
      await http.post(
        "/api/v1/profile/change-password",
        {
          currentPassword: form.currentPassword,
          newPassword: form.newPassword,
        },
        {
          meta: { suppressError: true },
        }
      );
      notify.success(t("auth.password_reset_success"));
      clearSession();
      const loginPath = getLoginPath();
      window.location.href = loginPath;
    } catch (err) {
      const resp = err?.response;
      const data = resp?.data;
      const status = resp?.status ?? null;

      // Attempt to resolve a user-friendly message
      const msg =
        resolveErrorMessage(data, status) || t("errors.UNKNOWN_ERROR");

      // Heuristic: detect common field-level errors and show them under the field
      // Backend might return:
      // { error: "INVALID_CURRENT_PASSWORD" } OR { code: "CURRENT_PASSWORD_INCORRECT" }
      // OR validation errors { errors: { currentPassword: ["..."] } }
      let handledField = false;

      if (data && typeof data === "object") {
        // Check "errors" object (typical validation format)
        if (data.errors && typeof data.errors === "object") {
          const cpErr =
            data.errors.currentPassword ||
            data.errors.current_password ||
            data.errors.current ||
            null;
          if (cpErr) {
            const cpMsg = Array.isArray(cpErr) ? cpErr[0] : String(cpErr);
            setFieldErrors((f) => ({ ...f, currentPassword: cpMsg }));
            handledField = true;
          }
        }

        const possibleCode =
          String(data.error || data.code || data.message || "").toUpperCase() ||
          "";
        if (
          /CURRENT_PASSWORD|INVALID_CURRENT|PASSWORD_INCORRECT|WRONG_PASSWORD/.test(
            possibleCode
          )
        ) {
          const friendly = t("errors.INVALID_CURRENT_PASSWORD", {
            defaultValue: "Current password is incorrect",
          });
          setFieldErrors((f) => ({ ...f, currentPassword: friendly }));
          handledField = true;
        }
      }

      if (!handledField) {
        notify.error(msg);
        setServerError(msg);
      }
    } finally {
      setSaving(false);
    }
  };

  return (
    <>
      <style>{`
        @keyframes fadeIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
        @keyframes slideIn { from { opacity: 0; transform: translateX(-10px); } to { opacity: 1; transform: translateX(0); } }
        .fade-in { animation: fadeIn 0.5s ease-out; }
        .slide-in { animation: slideIn 0.3s ease-out; }
      `}</style>

      <div className="fade-in">
        <div className="flex items-center gap-3 mb-8">
          <div className="p-3 rounded-2xl bg-gradient-to-br from-emerald-500 to-sky-600">
            <ShieldCheck className="w-8 h-8 text-white" />
          </div>
          <div>
            <h1 className="text-3xl font-bold bg-gradient-to-r from-emerald-600 to-sky-600 bg-clip-text text-transparent">
              {t("profile.change_password_title", {
                defaultValue: "Change Password",
              })}
            </h1>
            <p className="text-sm text-gray-500 mt-1">
              {t("profile.change_password_subtitle", {
                defaultValue:
                  "Update your password to keep your account secure",
              })}
            </p>
          </div>
        </div>

        <div className="w-full">
          <form onSubmit={onSubmit} className="space-y-6">
            <div className="space-y-2">
              <label className="block text-sm font-medium text-gray-700">
                {t("profile.current_password", {
                  defaultValue: "Current Password",
                })}{" "}
                *
              </label>
              <div className="relative">
                <Lock className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                <input
                  type={showPassword.current ? "text" : "password"}
                  name="currentPassword"
                  value={form.currentPassword}
                  onChange={onChange}
                  required
                  placeholder={t("profile.current_password_placeholder", {
                    defaultValue: "Enter your current password",
                  })}
                  className={`w-full rounded-xl border-2 pl-10 pr-12 py-3 focus:outline-none transition-colors ${
                    fieldErrors.currentPassword
                      ? "border-red-300 focus:border-red-500"
                      : "border-gray-200 focus:border-emerald-500"
                  }`}
                />
                <button
                  type="button"
                  onClick={() => toggleShowPassword("current")}
                  className="absolute right-3 top-3.5 text-gray-400 hover:text-gray-600 transition-colors"
                >
                  {showPassword.current ? (
                    <EyeOff className="w-5 h-5" />
                  ) : (
                    <Eye className="w-5 h-5" />
                  )}
                </button>
              </div>

              {fieldErrors.currentPassword && (
                <p className="text-sm text-red-600 flex items-center gap-1 slide-in mt-2">
                  <AlertCircle className="w-4 h-4" />
                  {fieldErrors.currentPassword}
                </p>
              )}
            </div>

            <div className="space-y-2">
              <label className="block text-sm font-medium text-gray-700">
                {t("profile.new_password", { defaultValue: "New Password" })} *
              </label>
              <div className="relative">
                <Lock className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                <input
                  type={showPassword.new ? "text" : "password"}
                  name="newPassword"
                  value={form.newPassword}
                  onChange={onChange}
                  required
                  placeholder={t("profile.new_password_placeholder", {
                    defaultValue: "Enter your new password",
                  })}
                  className="w-full rounded-xl border-2 border-gray-200 pl-10 pr-12 py-3 focus:border-emerald-500 focus:outline-none transition-colors"
                />
                <button
                  type="button"
                  onClick={() => toggleShowPassword("new")}
                  className="absolute right-3 top-3.5 text-gray-400 hover:text-gray-600 transition-colors"
                >
                  {showPassword.new ? (
                    <EyeOff className="w-5 h-5" />
                  ) : (
                    <Eye className="w-5 h-5" />
                  )}
                </button>
              </div>

              {form.newPassword && (
                <div className="mt-3 p-4 bg-gray-50 rounded-xl space-y-2 slide-in">
                  <p className="text-xs font-medium text-gray-700 mb-2">
                    {t("profile.password_requirements", {
                      defaultValue: "Password Requirements:",
                    })}
                  </p>
                  <div className="space-y-1.5">
                    <div className="flex items-center gap-2 text-sm">
                      {passwordChecks.length ? (
                        <CheckCircle2 className="w-4 h-4 text-emerald-500" />
                      ) : (
                        <AlertCircle className="w-4 h-4 text-gray-400" />
                      )}
                      <span
                        className={
                          passwordChecks.length
                            ? "text-emerald-700"
                            : "text-gray-600"
                        }
                      >
                        {t("profile.req_length", {
                          defaultValue: "Between 8 and 128 characters",
                        })}
                      </span>
                    </div>
                    <div className="flex items-center gap-2 text-sm">
                      {passwordChecks.uppercase ? (
                        <CheckCircle2 className="w-4 h-4 text-emerald-500" />
                      ) : (
                        <AlertCircle className="w-4 h-4 text-gray-400" />
                      )}
                      <span
                        className={
                          passwordChecks.uppercase
                            ? "text-emerald-700"
                            : "text-gray-600"
                        }
                      >
                        {t("profile.req_uppercase", {
                          defaultValue: "One uppercase letter",
                        })}
                      </span>
                    </div>
                    <div className="flex items-center gap-2 text-sm">
                      {passwordChecks.lowercase ? (
                        <CheckCircle2 className="w-4 h-4 text-emerald-500" />
                      ) : (
                        <AlertCircle className="w-4 h-4 text-gray-400" />
                      )}
                      <span
                        className={
                          passwordChecks.lowercase
                            ? "text-emerald-700"
                            : "text-gray-600"
                        }
                      >
                        {t("profile.req_lowercase", {
                          defaultValue: "One lowercase letter",
                        })}
                      </span>
                    </div>
                    <div className="flex items-center gap-2 text-sm">
                      {passwordChecks.number ? (
                        <CheckCircle2 className="w-4 h-4 text-emerald-500" />
                      ) : (
                        <AlertCircle className="w-4 h-4 text-gray-400" />
                      )}
                      <span
                        className={
                          passwordChecks.number
                            ? "text-emerald-700"
                            : "text-gray-600"
                        }
                      >
                        {t("profile.req_number", {
                          defaultValue: "One number",
                        })}
                      </span>
                    </div>
                  </div>
                </div>
              )}
            </div>

            <div className="space-y-2">
              <label className="block text-sm font-medium text-gray-700">
                {t("profile.confirm_new_password", {
                  defaultValue: "Confirm New Password",
                })}{" "}
                *
              </label>
              <div className="relative">
                <Lock className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                <input
                  type={showPassword.confirm ? "text" : "password"}
                  name="confirm"
                  value={form.confirm}
                  onChange={onChange}
                  required
                  placeholder={t("profile.confirm_new_password_placeholder", {
                    defaultValue: "Re-enter your new password",
                  })}
                  className={`w-full rounded-xl border-2 pl-10 pr-12 py-3 focus:outline-none transition-colors ${
                    form.confirm && form.newPassword !== form.confirm
                      ? "border-red-300 focus:border-red-500"
                      : "border-gray-200 focus:border-emerald-500"
                  }`}
                />
                <button
                  type="button"
                  onClick={() => toggleShowPassword("confirm")}
                  className="absolute right-3 top-3.5 text-gray-400 hover:text-gray-600 transition-colors"
                >
                  {showPassword.confirm ? (
                    <EyeOff className="w-5 h-5" />
                  ) : (
                    <Eye className="w-5 h-5" />
                  )}
                </button>
              </div>

              {form.confirm && form.newPassword !== form.confirm && (
                <p className="text-sm text-red-600 flex items-center gap-1 slide-in">
                  <AlertCircle className="w-4 h-4" />
                  {t("profile.passwords_do_not_match", {
                    defaultValue: "Passwords do not match",
                  })}
                </p>
              )}
              {form.confirm && form.newPassword === form.confirm && (
                <p className="text-sm text-emerald-600 flex items-center gap-1 slide-in">
                  <CheckCircle2 className="w-4 h-4" />
                  {t("profile.passwords_match", {
                    defaultValue: "Passwords match",
                  })}
                </p>
              )}
            </div>

            {serverError && (
              <div className="p-3 bg-red-50 border border-red-100 rounded-md text-sm text-red-700">
                {serverError}
              </div>
            )}

            <div className="flex items-center justify-end gap-4 pt-4 border-t">
              <button
                type="button"
                onClick={() => window.history.back()}
                className="px-6 py-3 rounded-xl text-gray-700 font-medium hover:bg-gray-100 transition-colors"
              >
                {t("common.cancel")}
              </button>
              <button
                type="submit"
                disabled={
                  saving ||
                  !allChecksPassed ||
                  form.newPassword !== form.confirm ||
                  !form.currentPassword
                }
                className="px-6 py-3 rounded-xl text-white font-medium shadow-lg transition-all bg-gradient-to-r from-emerald-500 to-sky-600 hover:from-sky-600 hover:to-emerald-500 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {saving ? (
                  <span className="flex items-center gap-2">
                    <svg className="animate-spin h-5 w-5" viewBox="0 0 24 24">
                      <circle
                        className="opacity-25"
                        cx="12"
                        cy="12"
                        r="10"
                        stroke="currentColor"
                        strokeWidth="4"
                        fill="none"
                      />
                      <path
                        className="opacity-75"
                        fill="currentColor"
                        d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                      />
                    </svg>
                    {t("common.loading")}
                  </span>
                ) : (
                  t("profile.update_password_cta", {
                    defaultValue: "Update Password",
                  })
                )}
              </button>
            </div>
          </form>
        </div>
      </div>
    </>
  );
}

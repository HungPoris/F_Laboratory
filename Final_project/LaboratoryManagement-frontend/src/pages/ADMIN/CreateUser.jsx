import React, { useEffect, useMemo, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useTranslation } from "react-i18next";
import Swal from "sweetalert2";
import { toast, ToastContainer } from "react-toastify";
import "react-toastify/dist/ReactToastify.css";
import http from "../../lib/api";
import { getAccessToken, clearSession } from "../../lib/auth";
import { fetchRoles, createUser, sendWelcome } from "../../services/adminApi";
import {
  User,
  Mail,
  Phone,
  Calendar,
  CreditCard,
  MapPin,
  Home,
  Shield,
  UserCheck,
} from "lucide-react";
import Loading from "../../components/Loading";

function unaccent(input = "") {
  return String(input)
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/đ/g, "d")
    .replace(/Đ/g, "D");
}

function useDebouncedValue(value, delay = 300) {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const id = setTimeout(() => setDebounced(value), delay);
    return () => clearTimeout(id);
  }, [value, delay]);
  return debounced;
}

function useClickOutside(onOutside) {
  const ref = useRef(null);
  useEffect(() => {
    function handler(e) {
      if (ref.current && !ref.current.contains(e.target)) onOutside();
    }
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [onOutside]);
  return ref;
}

function getErrorMessage(error, t) {
  if (error?.response?.data?.code) {
    const errorCode = error.response.data.code;
    const errorKey = `errors.${errorCode}`;
    if (t(errorKey) !== errorKey) {
      return t(errorKey);
    }
  }
  if (error?.response?.data?.message) {
    const message = error.response.data.message;
    const errorKey = `errors.${message}`;
    if (t(errorKey) !== errorKey) {
      return t(errorKey);
    }
  }
  if (error?.message === "Network Error" || !error?.response) {
    return t("errors.NETWORK_ERROR");
  }
  if (error?.response?.status === 401) {
    return t("errors.UNAUTHORIZED");
  }
  if (error?.response?.status === 403) {
    return t("errors.FORBIDDEN");
  }
  if (error?.response?.status === 404) {
    return t("errors.USER_NOT_FOUND");
  }
  return t("errors.GENERAL_ERROR");
}

function cleanAddress(input = "") {
  return String(input)
    .replace(/\s+/g, " ")
    .replace(/[\r\n\t]+/g, " ")
    .trim();
}

function SearchableSelect({
  value,
  onChange,
  options,
  placeholder,
  disabled,
  loading,
  noOptionsText,
  searchPlaceholder,
  renderIcon,
  clearable = true,
  className = "",
  debounceMs = 300,
}) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [focusIdx, setFocusIdx] = useState(-1);
  const debouncedQuery = useDebouncedValue(query, debounceMs);
  const ref = useClickOutside(() => {
    setOpen(false);
    setQuery("");
    setFocusIdx(-1);
  });

  const selected = useMemo(
    () => options.find((o) => String(o.value) === String(value)) || null,
    [options, value]
  );

  const filtered = useMemo(() => {
    if (!debouncedQuery.trim()) return options;
    const q = unaccent(debouncedQuery.trim().toLowerCase());
    return options.filter((o) =>
      unaccent(String(o.label).toLowerCase()).includes(q)
    );
  }, [options, debouncedQuery]);

  useEffect(() => {
    if (!open) {
      setQuery("");
      setFocusIdx(-1);
    }
  }, [open]);

  function handleKeyDown(e) {
    if (!open) {
      if (e.key === "ArrowDown" || e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        setOpen(true);
        setFocusIdx(0);
      }
      return;
    }
    if (e.key === "Escape") {
      e.preventDefault();
      setOpen(false);
      return;
    }
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setFocusIdx((i) => Math.min(i + 1, filtered.length - 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setFocusIdx((i) => Math.max(i - 1, 0));
    } else if (e.key === "Enter") {
      e.preventDefault();
      if (filtered[focusIdx]) {
        onChange(filtered[focusIdx].value);
        setOpen(false);
      }
    }
  }

  return (
    <div ref={ref} className={`relative ${className}`}>
      <button
        type="button"
        disabled={disabled}
        onClick={() => setOpen((v) => !v)}
        onKeyDown={handleKeyDown}
        className={`w-full rounded-xl border-2 px-4 py-3 text-left transition-all
          ${
            disabled
              ? "bg-gray-50 cursor-not-allowed"
              : "bg-white hover:border-emerald-400"
          }
          ${open ? "border-emerald-500" : "border-gray-200"}`}
        aria-haspopup="listbox"
        aria-expanded={open}
      >
        <div className="flex items-center gap-2">
          {renderIcon ? (
            <span className="text-gray-400">{renderIcon}</span>
          ) : null}
          <span className={`${selected ? "text-gray-900" : "text-gray-400"}`}>
            {selected ? selected.label : placeholder || ""}
          </span>
          <span className="ml-auto text-gray-400">
            {loading ? "…" : open ? "▲" : "▼"}
          </span>
          {clearable && selected && !disabled && (
            <span
              onClick={(e) => {
                e.stopPropagation();
                onChange("");
              }}
              className="ml-2 text-gray-400 hover:text-gray-600 px-2"
              role="button"
              aria-label="Clear"
              title="Clear"
            >
              ×
            </span>
          )}
        </div>
      </button>

      {open && (
        <div
          className="absolute z-50 mt-2 w-full rounded-xl border-2 border-emerald-200 bg-white shadow-xl"
          role="listbox"
        >
          <div className="p-2">
            <input
              autoFocus
              value={query}
              onChange={(e) => {
                setQuery(e.target.value);
                setFocusIdx(0);
              }}
              onKeyDown={handleKeyDown}
              placeholder={searchPlaceholder || "Search..."}
              className="w-full rounded-lg border-2 border-gray-200 px-3 py-2 focus:outline-none focus:border-emerald-500"
            />
          </div>
          <div className="max-h-64 overflow-auto py-1">
            {loading ? (
              <div className="px-3 py-2 text-sm text-gray-500">Loading...</div>
            ) : filtered.length === 0 ? (
              <div className="px-3 py-2 text-sm text-gray-500">
                {noOptionsText || "No options"}
              </div>
            ) : (
              filtered.map((o, idx) => (
                <div
                  key={o.value}
                  role="option"
                  aria-selected={String(o.value) === String(value)}
                  onMouseEnter={() => setFocusIdx(idx)}
                  onMouseDown={(e) => e.preventDefault()}
                  onClick={() => {
                    onChange(o.value);
                    setOpen(false);
                  }}
                  className={`px-3 py-2 cursor-pointer
                    ${idx === focusIdx ? "bg-emerald-50" : ""}
                    ${
                      String(o.value) === String(value)
                        ? "font-medium text-emerald-700"
                        : "text-gray-700"
                    }`}
                >
                  {o.label}
                </div>
              ))
            )}
          </div>
        </div>
      )}
    </div>
  );
}

export default function CreateUser() {
  const { t } = useTranslation();
  const navigate = useNavigate();

  const [roles, setRoles] = useState([]);
  const [loadingRoles, setLoadingRoles] = useState(false);
  const [roleError, setRoleError] = useState(null);
  const [provinces, setProvinces] = useState([]);
  const [communes, setCommunes] = useState([]);
  const [loadingCommune, setLoadingCommune] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  const [form, setForm] = useState({
    username: "",
    fullName: "",
    email: "",
    phoneNumber: "",
    dateOfBirth: "",
    identityNumber: "",
    gender: "",
    house: "",
    provinceCode: "",
    communeCode: "",
    roleCode: "",
    enabled: true,
  });

  const [errors, setErrors] = useState({});
  const [usernameChecking, setUsernameChecking] = useState(false);
  const [usernameExists, setUsernameExists] = useState(false);

  function asArray(raw) {
    if (Array.isArray(raw)) return raw;
    if (Array.isArray(raw?.content)) return raw.content;
    if (Array.isArray(raw?.data)) return raw.data;
    if (Array.isArray(raw?.items)) return raw.items;
    if (Array.isArray(raw?.results)) return raw.results;
    if (raw && typeof raw === "object") return Object.values(raw);
    return [];
  }

  useEffect(() => {
    let mounted = true;
    setLoadingRoles(true);
    setRoleError(null);

    fetchRoles()
      .then((r) => {
        if (!mounted) return;
        const list = Array.isArray(r) ? r : r?.content || asArray(r);
        setRoles(list);
        setRoleError(null);
      })
      .catch((err) => {
        if (!mounted) return;
        const errorMsg =
          getErrorMessage(err, t) || t("errors.FETCH_ROLES_FAILED");
        setRoleError(errorMsg);
        toast.error(errorMsg);
      })
      .finally(() => {
        if (mounted) setLoadingRoles(false);
      });

    http
      .get("/api/v1/addresses/provinces")
      .then((res) => {
        if (!mounted) return;
        const data = asArray(res?.data?.provinces ?? res?.data);
        setProvinces(data);
      })
      .catch((err) => {
        if (!mounted) return;
        setProvinces([]);
        toast.error(
          getErrorMessage(err, t) || t("errors.FETCH_PROVINCES_FAILED")
        );
      });

    return () => (mounted = false);
  }, [t]);

  useEffect(() => {
    const { provinceCode } = form;
    if (!provinceCode) {
      setCommunes([]);
      return;
    }
    setLoadingCommune(true);
    http
      .get("/api/v1/addresses/communes", {
        params: { provinceCode, size: 500, page: 0 },
      })
      .then((res) => {
        const data = asArray(res?.data?.communes ?? res?.data);
        setCommunes(data);
      })
      .catch((err) => {
        setCommunes([]);
        toast.error(
          getErrorMessage(err, t) || t("errors.FETCH_COMMUNES_FAILED")
        );
      })
      .finally(() => setLoadingCommune(false));
  }, [form.provinceCode, t]);

  const debouncedUsername = useDebouncedValue(form.username, 500);

  useEffect(() => {
    let mounted = true;
    async function check() {
      const raw = String(debouncedUsername || "").trim();
      if (!raw) {
        if (!mounted) return;
        setUsernameExists(false);
        setUsernameChecking(false);
        setErrors((prev) => {
          const copy = { ...prev };
          delete copy.username;
          return copy;
        });
        return;
      }
      setUsernameChecking(true);
      try {
        const res = await http.get("/api/v1/admin/users", {
          params: { q: raw, page: 0, size: 10 },
        });
        const list = Array.isArray(res?.data)
          ? res.data
          : res?.data?.content || asArray(res?.data);
        const found =
          Array.isArray(list) &&
          list.some((u) => {
            const uname =
              u.username ||
              u.userName ||
              (u.user && (u.user.username || u.user.userName)) ||
              "";
            return String(uname).trim().toLowerCase() === raw.toLowerCase();
          });
        if (!mounted) return;
        setUsernameExists(found);
        setUsernameChecking(false);
        setErrors((prev) => {
          const copy = { ...prev };
          if (found) {
            copy.username = "Username already exists";
          } else {
            if (copy.username === "Username already exists") {
              delete copy.username;
            }
          }
          return copy;
        });
        // eslint-disable-next-line no-unused-vars
      } catch (err) {
        if (!mounted) return;
        setUsernameChecking(false);
      }
    }
    check();
    return () => {
      mounted = false;
    };
  }, [debouncedUsername]);

  function validate() {
    const e = {};

    const fullNameRaw = String(form.fullName || "").trim();
    if (fullNameRaw.length < 2) {
      e.fullName = "Full name must be at least 2 characters";
    } else if (!/^[\p{L}\s'.-]+$/u.test(fullNameRaw)) {
      e.fullName = "Full name cannot contain invalid characters";
    }

    const usernameRaw = String(form.username || "").trim();
    if (usernameRaw) {
      if (usernameRaw.length < 3) {
        e.username = "Username must be at least 3 characters";
      } else if (!/^[a-zA-Z0-9._-]+$/.test(usernameRaw)) {
        e.username = "Username contains invalid characters";
      }
      if (usernameExists) {
        e.username = "Username already exists";
      }
    }

    const emailRaw = String(form.email || "").trim();
    const emailRegex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[A-Za-z]{2,}$/;
    if (!emailRaw || !emailRegex.test(emailRaw)) {
      e.email = "Invalid email address";
    }

    if (!form.roleCode) e.roleCode = "Role is required";
    if (!form.provinceCode) e.provinceCode = "Province/City is required";

    const phoneRaw = String(form.phoneNumber || "").trim();
    if (phoneRaw) {
      if (!/^\d{10}$/.test(phoneRaw)) {
        e.phoneNumber = "Phone must be exactly 10 digits";
      }
    }

    const idRaw = String(form.identityNumber || "").trim();
    if (idRaw) {
      if (!/^\d{12}$/.test(idRaw)) {
        e.identityNumber = "Citizen ID/Passport must be exactly 12 digits";
      }
    }

    setErrors(e);
    return Object.keys(e).length === 0;
  }

  function getProvinceByCode(code) {
    const list = Array.isArray(provinces) ? provinces : asArray(provinces);
    return list.find((p) => String(p.code) === String(code)) || null;
  }

  function getCommuneByCode(code) {
    const list = Array.isArray(communes) ? communes : asArray(communes);
    return list.find((c) => String(c.code) === String(code)) || null;
  }

  function retryLoadRoles() {
    setLoadingRoles(true);
    setRoleError(null);
    fetchRoles()
      .then((r) => {
        const list = Array.isArray(r) ? r : r?.content || asArray(r);
        setRoles(list);
        setRoleError(null);
        toast.success(t("admin.roles_reload_success"));
      })
      .catch((err) => {
        const errorMsg =
          getErrorMessage(err, t) || t("errors.FETCH_ROLES_FAILED");
        setRoleError(errorMsg);
        toast.error(errorMsg);
      })
      .finally(() => setLoadingRoles(false));
  }

  async function onSubmit(ev) {
    ev && ev.preventDefault();
    try {
      const tk = getAccessToken();
      if (!tk || String(tk).trim().length === 0) {
        toast.error(t("errors.SESSION_EXPIRED"));
        try {
          clearSession();
          delete http.defaults.headers.common.Authorization;
        } catch {
          /* empty */
        }
        navigate("/login");
        return;
      }
    } catch {
      /* empty */
    }

    if (!validate()) return;
    setSubmitting(true);
    try {
      const prov = getProvinceByCode(form.provinceCode);
      const comm = getCommuneByCode(form.communeCode);
      const cleanedHouse = cleanAddress(form.house || "");
      const parts = [];
      if (cleanedHouse) parts.push(cleanedHouse);
      if (comm && comm.name) parts.push(comm.name);
      if (prov && prov.name) parts.push(prov.name);
      const fullAddress = parts.join(", ");

      const genderDb =
        form.gender === "FEMALE"
          ? "female"
          : form.gender === "MALE"
          ? "male"
          : form.gender === "OTHER"
          ? null
          : form.gender || null;

      const payload = {
        ...(form.username && form.username.trim() !== ""
          ? { username: form.username.trim() }
          : {}),
        fullName: form.fullName,
        email: form.email,
        phoneNumber: form.phoneNumber || null,
        dateOfBirth: form.dateOfBirth || null,
        identityNumber: form.identityNumber || null,
        gender: genderDb,
        address: fullAddress,
        roles: form.roleCode ? [form.roleCode] : [],
      };

      const res = await createUser(payload, { revealPassword: true });
      const userId = res?.id || res?.user?.userId || res?.user?.id;
      const generatedPassword = res?.password || res?.user?.password || null;
      const username =
        res?.username ||
        (res?.user && (res.user.username || res.user.userName)) ||
        payload.username ||
        "";
      const fullName =
        res?.fullName ||
        (res?.user && res.user.fullName) ||
        payload.fullName ||
        "";

      if (!userId) throw new Error(t("errors.CREATE_USER_FAILED"));

      try {
        await sendWelcome(
          userId,
          generatedPassword ? { password: generatedPassword } : {}
        );
        toast.success(t("admin.welcome_email_sent"));
      } catch (sendErr) {
        const sendMsg =
          getErrorMessage(sendErr, t) || t("errors.SEND_WELCOME_EMAIL_FAILED");
        toast.warn(sendMsg);
      }

      Swal.fire(
        t("admin.success"),
        t("admin.user_created_success", { name: username || fullName }),
        "success"
      );

      setForm({
        username: "",
        fullName: "",
        email: "",
        phoneNumber: "",
        dateOfBirth: "",
        identityNumber: "",
        gender: "",
        house: "",
        provinceCode: "",
        communeCode: "",
        roleCode: "",
        enabled: true,
      });
      setCommunes([]);
      setErrors({});
      setUsernameExists(false);
    } catch (err) {
      const msg = getErrorMessage(err, t) || t("errors.CREATE_USER_FAILED");
      Swal.fire(t("admin.error"), msg, "error");
    } finally {
      setSubmitting(false);
    }
  }

  const safeProvinces = Array.isArray(provinces)
    ? provinces
    : asArray(provinces);
  const safeCommunes = Array.isArray(communes) ? communes : asArray(communes);

  const provinceOptions = safeProvinces.map((p) => ({
    value: p.code,
    label: p.name,
  }));
  const communeOptions = safeCommunes.map((c) => ({
    value: c.code,
    label: c.name,
  }));

  return (
    <>
      <style>{`
        @keyframes fade-in { from { opacity:.0; transform: translateY(10px) } to { opacity:1; transform: translateY(0) } }
        .fade-in { animation: fade-in .5s ease-out }
      `}</style>

      <div className="min-h-screen bg-gradient-to-br from-emerald-50 via-sky-50 to-indigo-50 p-6">
        <ToastContainer position="top-right" pauseOnHover />
        <div className="max-w-7xl mx-auto">
          <div className="bg-white rounded-3xl shadow-xl p-8 fade-in">
            <div className="flex items-center gap-3 mb-8">
              <div className="p-3 rounded-2xl bg-gradient-to-br from-emerald-500 to-sky-600">
                <UserCheck className="w-8 h-8 text-white" />
              </div>
              <div>
                <h1 className="text-3xl font-bold bg-gradient-to-r from-emerald-600 to-sky-600 bg-clip-text text-transparent">
                  {t("admin.create_user")}
                </h1>
                <p className="text-sm text-gray-500 mt-1">
                  {t("admin.create_user_subtitle")}
                </p>
              </div>
            </div>

            <form onSubmit={onSubmit} className="space-y-6">
              <div className="space-y-4">
                <h3 className="text-lg font-semibold text-gray-700 flex items-center gap-2">
                  <User className="w-5 h-5 text-emerald-500" />
                  {t("admin.login_info")}
                </h3>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      {t("admin.full_name")}{" "}
                      <span className="text-red-500">*</span>
                    </label>
                    <div className="relative">
                      <User className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                      <input
                        value={form.fullName}
                        onChange={(e) =>
                          setForm({ ...form, fullName: e.target.value })
                        }
                        placeholder={t("admin.full_name_placeholder")}
                        className="w-full rounded-xl border-2 border-gray-200 pl-10 pr-4 py-3 focus:border-emerald-500 focus:outline-none transition-all"
                      />
                    </div>
                    {errors.fullName && (
                      <div className="text-sm text-red-600 mt-1">
                        {errors.fullName}
                      </div>
                    )}
                  </div>

                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      {t("admin.username")}{" "}
                      <span className="text-xs text-gray-500 ml-2">
                        {t("admin.username_optional")}
                      </span>
                    </label>
                    <div className="relative">
                      <User className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                      <input
                        value={form.username}
                        onChange={(e) =>
                          setForm({ ...form, username: e.target.value })
                        }
                        placeholder={t("admin.username_placeholder")}
                        className="w-full rounded-xl border-2 border-gray-200 pl-10 pr-10 py-3 focus:border-emerald-500 focus:outline-none transition-all"
                      />
                      <div className="absolute right-3 top-3.5 flex items-center gap-2">
                        {usernameChecking ? (
                          <div className="text-sm text-gray-400">Checking…</div>
                        ) : usernameExists ? (
                          <div className="text-sm text-red-600">Taken</div>
                        ) : form.username ? (
                          <div className="text-sm text-green-600">
                            Available
                          </div>
                        ) : null}
                      </div>
                    </div>
                    {errors.username && (
                      <div className="text-sm text-red-600 mt-1">
                        {errors.username}
                      </div>
                    )}
                  </div>
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    {t("admin.email")} <span className="text-red-500">*</span>
                  </label>
                  <div className="relative">
                    <Mail className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                    <input
                      value={form.email}
                      onChange={(e) =>
                        setForm({ ...form, email: e.target.value })
                      }
                      placeholder={t("admin.email_placeholder")}
                      className="w-full rounded-xl border-2 border-gray-200 pl-10 pr-4 py-3 focus:border-emerald-500 focus:outline-none transition-all"
                    />
                  </div>
                  {errors.email && (
                    <div className="text-sm text-red-600 mt-1">
                      {errors.email}
                    </div>
                  )}
                </div>
              </div>

              <div className="space-y-4 pt-6 border-t">
                <h3 className="text-lg font-semibold text-gray-700 flex items-center gap-2">
                  <CreditCard className="w-5 h-5 text-sky-500" />
                  {t("admin.personal_info")}
                </h3>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      {t("admin.phone_number")}
                    </label>
                    <div className="relative">
                      <Phone className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                      <input
                        value={form.phoneNumber}
                        onChange={(e) =>
                          setForm({ ...form, phoneNumber: e.target.value })
                        }
                        placeholder={t("admin.phone_placeholder")}
                        className="w-full rounded-xl border-2 border-gray-200 pl-10 pr-4 py-3 focus:border-emerald-500 focus:outline-none transition-all"
                      />
                    </div>
                    {errors.phoneNumber && (
                      <div className="text-sm text-red-600 mt-1">
                        {errors.phoneNumber}
                      </div>
                    )}
                  </div>

                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      {t("admin.date_of_birth")}
                    </label>
                    <div className="relative">
                      <Calendar className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                      <input
                        type="date"
                        value={form.dateOfBirth}
                        onChange={(e) =>
                          setForm({ ...form, dateOfBirth: e.target.value })
                        }
                        className="w-full rounded-xl border-2 border-gray-200 pl-10 pr-4 py-3 focus:border-emerald-500 focus:outline-none transition-all"
                      />
                    </div>
                  </div>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      {"Citizen ID / Passport Number"}
                    </label>
                    <div className="relative">
                      <CreditCard className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                      <input
                        value={form.identityNumber}
                        onChange={(e) =>
                          setForm({ ...form, identityNumber: e.target.value })
                        }
                        placeholder={"Citizen ID / Passport Number"}
                        className="w-full rounded-xl border-2 border-gray-200 pl-10 pr-4 py-3 focus:border-emerald-500 focus:outline-none transition-all"
                      />
                    </div>
                    {errors.identityNumber && (
                      <div className="text-sm text-red-600 mt-1">
                        {errors.identityNumber}
                      </div>
                    )}
                  </div>

                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      {t("admin.gender")}
                    </label>
                    <select
                      value={form.gender}
                      onChange={(e) =>
                        setForm({ ...form, gender: e.target.value })
                      }
                      className="w-full rounded-xl border-2 border-gray-200 px-4 py-3 focus:border-emerald-500 focus:outline-none transition-all"
                    >
                      <option value="">{t("admin.gender_select")}</option>
                      <option value="MALE">{t("admin.gender_male")}</option>
                      <option value="FEMALE">{t("admin.gender_female")}</option>
                      <option value="OTHER">{t("admin.gender_other")}</option>
                    </select>
                  </div>
                </div>
              </div>

              <div className="space-y-4 pt-6 border-t">
                <h3 className="text-lg font-semibold text-gray-700 flex items-center gap-2">
                  <MapPin className="w-5 h-5 text-emerald-500" />
                  {t("admin.address_info")}
                </h3>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      {t("admin.province")}{" "}
                      <span className="text-red-500">*</span>
                    </label>
                    <SearchableSelect
                      value={form.provinceCode}
                      onChange={(val) =>
                        setForm({
                          ...form,
                          provinceCode: val,
                          communeCode: "",
                        })
                      }
                      options={provinceOptions}
                      placeholder={t("admin.province_select")}
                      searchPlaceholder={
                        t("common.search_placeholder") || "Type to search..."
                      }
                      noOptionsText={"No results"}
                      loading={false}
                      disabled={false}
                      renderIcon={<MapPin className="w-5 h-5" />}
                      debounceMs={250}
                    />
                    {errors.provinceCode && (
                      <div className="text-sm text-red-600 mt-1">
                        {errors.provinceCode}
                      </div>
                    )}
                  </div>

                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      {t("admin.commune")}
                    </label>
                    <SearchableSelect
                      value={form.communeCode}
                      onChange={(val) => setForm({ ...form, communeCode: val })}
                      options={communeOptions}
                      placeholder={t("admin.commune_select")}
                      searchPlaceholder={
                        t("common.search_placeholder") || "Type to search..."
                      }
                      noOptionsText={"No results"}
                      loading={loadingCommune}
                      disabled={!form.provinceCode}
                      renderIcon={<MapPin className="w-5 h-5" />}
                      debounceMs={250}
                    />
                  </div>
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    {t("admin.house_number")}
                  </label>
                  <div className="relative">
                    <Home className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                    <input
                      value={form.house}
                      onChange={(e) =>
                        setForm({ ...form, house: e.target.value })
                      }
                      placeholder={t("admin.house_placeholder")}
                      maxLength={255}
                      className="w-full rounded-xl border-2 border-gray-200 pl-10 pr-4 py-3 focus:border-emerald-500 focus:outline-none transition-all"
                    />
                  </div>
                </div>
              </div>

              <div className="space-y-4 pt-6 border-t">
                <h3 className="text-lg font-semibold text-gray-700 flex items-center gap-2">
                  <Shield className="w-5 h-5 text-emerald-500" />
                  {t("admin.role_security")}
                </h3>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    {t("admin.role")} <span className="text-red-500">*</span>
                  </label>
                  {loadingRoles ? (
                    <div className="flex items-center justify-center p-6 border-2 border-dashed rounded-xl bg-gray-50">
                      <Loading size={40} />
                    </div>
                  ) : roleError ? (
                    <div className="p-4 border-2 border-red-200 rounded-xl bg-red-50">
                      <div className="text-sm text-red-700 mb-3">
                        {roleError}
                      </div>
                      <button
                        type="button"
                        onClick={retryLoadRoles}
                        className="text-sm px-4 py-2 rounded-lg bg-red-600 text-white hover:bg-red-700 transition"
                      >
                        {t("common.retry")}
                      </button>
                    </div>
                  ) : roles.length === 0 ? (
                    <div className="p-4 border-2 border-yellow-200 rounded-xl bg-yellow-50">
                      <div className="text-sm text-yellow-700 mb-3">
                        {t("admin.no_roles_available")}
                      </div>
                      <button
                        type="button"
                        onClick={retryLoadRoles}
                        className="text-sm px-4 py-2 rounded-lg bg-yellow-600 text-white hover:bg-yellow-700 transition"
                      >
                        {t("common.reload")}
                      </button>
                    </div>
                  ) : (
                    <select
                      value={form.roleCode}
                      onChange={(e) =>
                        setForm({ ...form, roleCode: e.target.value })
                      }
                      className="w-full rounded-xl border-2 border-gray-200 px-4 py-3 focus:border-emerald-500 focus:outline-none transition-all"
                    >
                      <option value="">{t("admin.role_select")}</option>
                      {roles.map((r) => {
                        const code = r.code || r.roleCode || r.id;
                        return (
                          <option key={code} value={code}>
                            {r.name ||
                              r.displayName ||
                              r.code ||
                              r.roleCode ||
                              r.id}
                          </option>
                        );
                      })}
                    </select>
                  )}
                  {errors.roleCode && (
                    <div className="text-sm text-red-600 mt-1">
                      {errors.roleCode}
                    </div>
                  )}
                </div>
              </div>

              <div className="flex items-center gap-4 justify-end pt-6 border-t">
                <button
                  type="button"
                  onClick={() => navigate(-1)}
                  className="px-6 py-3 rounded-xl border-2 border-gray-200 hover:border-gray-300 hover:bg-gray-50 transition-all font-medium"
                >
                  {t("common.cancel")}
                </button>
                <button
                  type="submit"
                  disabled={submitting || usernameExists}
                  className="px-8 py-3 rounded-xl text-white font-medium shadow-lg disabled:opacity-50 disabled:cursor-not-allowed transition-all bg-gradient-to-r from-emerald-500 to-sky-600 hover:from-sky-600 hover:to-emerald-500 flex items-center gap-2"
                >
                  {submitting ? (
                    <>
                      <Loading size={20} />
                      <span>{t("admin.submit_creating")}</span>
                    </>
                  ) : (
                    <>
                      <UserCheck className="w-5 h-5" />
                      <span>{t("admin.create_user")}</span>
                    </>
                  )}
                </button>
              </div>
            </form>
          </div>
        </div>
      </div>
    </>
  );
}

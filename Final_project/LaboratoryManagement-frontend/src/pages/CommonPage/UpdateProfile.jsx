import React, { useEffect, useMemo, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import Swal from "sweetalert2";
import { toast, ToastContainer } from "react-toastify";
import "react-toastify/dist/ReactToastify.css";
import http from "../../lib/api";
import { getAccessToken, clearSession } from "../../lib/auth";
import {
  User,
  Mail,
  Phone,
  Calendar,
  CreditCard,
  MapPin,
  Home,
  UserCheck,
} from "lucide-react";
import { useTranslation } from "react-i18next";

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

export default function UpdateProfile() {
  const { t } = useTranslation();
  const navigate = useNavigate();

  const [provinces, setProvinces] = useState([]);
  const [communes, setCommunes] = useState([]);
  const [loadingCommune, setLoadingCommune] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [loadingProfile, setLoadingProfile] = useState(true);
  const [oldAddress, setOldAddress] = useState("");

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
  });

  const [errors, setErrors] = useState({});

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
    setLoadingProfile(true);
    Promise.all([
      http.get("/api/v1/profile").catch(() => null),
      http.get("/api/v1/addresses/provinces").catch(() => null),
    ])
      .then(([profileRes, provRes]) => {
        if (!mounted) return;
        const p = profileRes?.data || {};
        setForm((prev) => ({
          ...prev,
          username: p.username || "",
          fullName: p.fullName || "",
          email: p.email || "",
          phoneNumber: p.phoneNumber || "",
          dateOfBirth: p.dateOfBirth || "",
          identityNumber: p.identityNumber || "",
          gender:
            (p.gender || "").toUpperCase() === "MALE"
              ? "MALE"
              : (p.gender || "").toUpperCase() === "FEMALE"
              ? "FEMALE"
              : (p.gender || "").toUpperCase() === "OTHER"
              ? "OTHER"
              : "",
          house: "",
          provinceCode: "",
          communeCode: "",
        }));
        setOldAddress(p.address || "");
        const provs = asArray(provRes?.data?.provinces ?? provRes?.data);
        setProvinces(provs);
      })
      .finally(() => setLoadingProfile(false));
    return () => {
      mounted = false;
    };
  }, []);

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
      .catch(() => {
        setCommunes([]);
        toast.error(t("errors.FETCH_COMMUNES_FAILED"));
      })
      .finally(() => setLoadingCommune(false));
  }, [form.provinceCode, t]);

  function validate() {
    const e = {};
    const name = form.fullName?.trim() || "";
    if (!name) e.fullName = t("admin.full_name_required");
    else if (name.length < 4 || name.length > 128)
      e.fullName = t("errors.FULL_NAME_SIZE");
    else if (!/^[\p{L}\s]+$/u.test(name))
      e.fullName = t("errors.FULL_NAME_PATTERN");

    const email = form.email?.trim() || "";
    if (!email) e.email = t("admin.email_required");
    else if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email))
      e.email = t("errors.EMAIL_INVALID");

    const phone = (form.phoneNumber || "").trim();
    if (phone && !/^\d{10}$/.test(phone))
      e.phoneNumber = t("errors.PHONE_INVALID");

    const idn = (form.identityNumber || "").trim();
    if (idn && !/^\d{12}$/.test(idn))
      e.identityNumber = t("errors.IDENTITY_INVALID");

    const dob = form.dateOfBirth;
    if (dob) {
      const d = new Date(dob);
      const today = new Date();
      if (
        isNaN(d.getTime()) ||
        d >= new Date(today.getFullYear(), today.getMonth(), today.getDate())
      ) {
        e.dateOfBirth = t("errors.DATE_OF_BIRTH_PAST");
      }
    }

    setErrors(e);
    return Object.keys(e).length === 0;
  }

  function resolveErrorMessage(responseData, httpStatus = null) {
    if (!responseData || typeof responseData !== "object") {
      if (httpStatus === 401) return t("errors.UNAUTHORIZED");
      if (httpStatus === 403) return t("errors.FORBIDDEN");
      if (httpStatus === 404) return t("errors.USER_NOT_FOUND");
      if (httpStatus === 500) return t("errors.UNKNOWN_ERROR");
      return t("errors.UNKNOWN_ERROR");
    }

    if (responseData.message && typeof responseData.message === "string") {
      const raw = responseData.message.trim();
      if (raw && !/^[A-Z0-9_]+$/.test(raw) && !/^[a-z0-9_]+$/.test(raw)) {
        return raw;
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
        /* empty */
      }
    }

    if (code) {
      const norm = String(code).trim().toUpperCase();
      const msg = t(`errors.${norm}`, { defaultValue: "" });
      if (msg && msg !== `errors.${norm}`) return msg;

      // field error map fallback (e.g. FULL_NAME_SIZE ...)
      const fieldMsg =
        t(`errors.${norm}`, { defaultValue: "" }) ||
        t("errors.VALIDATION_FAILED", { defaultValue: "" });
      if (fieldMsg) return fieldMsg;
    }

    if (httpStatus === 401) return t("errors.UNAUTHORIZED");
    if (httpStatus === 403) return t("errors.FORBIDDEN");
    return t("errors.UNKNOWN_ERROR");
  }

  function getProvinceByCode(code) {
    const list = Array.isArray(provinces) ? provinces : asArray(provinces);
    return list.find((p) => p.code === code) || null;
  }

  function getCommuneByCode(code) {
    const list = Array.isArray(communes) ? communes : asArray(communes);
    return list.find((c) => c.code === code) || null;
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
      const parts = [];
      if (form.house && form.house.trim().length > 0)
        parts.push(form.house.trim());
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
        fullName: form.fullName?.trim(),
        email: form.email?.trim(),
        phoneNumber: form.phoneNumber ? form.phoneNumber.trim() : null,
        dateOfBirth: form.dateOfBirth || null,
        identityNumber: form.identityNumber ? form.identityNumber.trim() : null,
        gender: genderDb,
        address: fullAddress || undefined,
      };

      await http.put("/api/v1/profile", payload);
      toast.success(t("profile.update_success"));
      await Swal.fire(
        t("common.success"),
        t("profile.update_success"),
        "success"
      );
      navigate("/profile");
    } catch (err) {
      const msg =
        resolveErrorMessage(err?.response?.data, err?.response?.status) ||
        t("profile.update_failed");
      Swal.fire(t("common.error"), msg, "error");
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

  if (loadingProfile) {
    return (
      <div className="py-16 flex items-center justify-center">
        <div className="w-10 h-10 border-2 border-gray-300 border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  return (
    <>
      <ToastContainer position="top-right" pauseOnHover />

      <div>
        <div className="flex items-center gap-3 mb-8">
          <div className="p-3 rounded-2xl bg-gradient-to-br from-emerald-500 to-sky-600">
            <UserCheck className="w-8 h-8 text-white" />
          </div>
          <div>
            <h1 className="text-3xl font-bold bg-gradient-to-r from-emerald-600 to-sky-600 bg-clip-text text-transparent">
              {t("profile.title")}
            </h1>
            <p className="text-sm text-gray-500 mt-1">
              {t("profile.subtitle")}
            </p>
          </div>
        </div>

        <form onSubmit={onSubmit} className="space-y-6">
          <div className="space-y-4">
            <h3 className="text-lg font-semibold text-gray-700 flex items-center gap-2">
              <User className="w-5 h-5 text-emerald-500" />
              {t("profile.section_signin")}
            </h3>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  {t("profile.username")}
                </label>
                <div className="relative">
                  <User className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                  <input
                    value={form.username}
                    readOnly
                    className="w-full rounded-xl border-2 border-gray-200 pl-10 pr-4 py-3 bg-gray-50"
                  />
                </div>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  {t("profile.full_name")}
                  <span className="text-red-500"> *</span>
                </label>
                <div className="relative">
                  <User className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                  <input
                    value={form.fullName}
                    onChange={(e) =>
                      setForm({ ...form, fullName: e.target.value })
                    }
                    placeholder={t("profile.placeholder_full_name")}
                    className="w-full rounded-xl border-2 border-gray-200 pl-10 pr-4 py-3 focus:border-emerald-500 focus:outline-none transition-all"
                  />
                </div>
                {errors.fullName && (
                  <div className="text-sm text-red-600 mt-1">
                    {errors.fullName}
                  </div>
                )}
              </div>
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                {t("profile.email")} <span className="text-red-500">*</span>
              </label>
              <div className="relative">
                <Mail className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                <input
                  value={form.email}
                  onChange={(e) => setForm({ ...form, email: e.target.value })}
                  placeholder={t("profile.placeholder_email")}
                  className="w-full rounded-xl border-2 border-gray-200 pl-10 pr-4 py-3 focus:border-emerald-500 focus:outline-none transition-all"
                />
              </div>
              {errors.email && (
                <div className="text-sm text-red-600 mt-1">{errors.email}</div>
              )}
            </div>
          </div>

          <div className="space-y-4 pt-6 border-t">
            <h3 className="text-lg font-semibold text-gray-700 flex items-center gap-2">
              <CreditCard className="w-5 h-5 text-sky-500" />
              {t("profile.section_personal")}
            </h3>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  {t("profile.phone_number")}
                </label>
                <div className="relative">
                  <Phone className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                  <input
                    value={form.phoneNumber}
                    onChange={(e) =>
                      setForm({ ...form, phoneNumber: e.target.value })
                    }
                    placeholder={t("profile.placeholder_phone")}
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
                  {t("profile.date_of_birth")}
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
                {errors.dateOfBirth && (
                  <div className="text-sm text-red-600 mt-1">
                    {errors.dateOfBirth}
                  </div>
                )}
              </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  {t("profile.identity_number")}
                </label>
                <div className="relative">
                  <CreditCard className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                  <input
                    value={form.identityNumber}
                    onChange={(e) =>
                      setForm({ ...form, identityNumber: e.target.value })
                    }
                    placeholder={t("profile.placeholder_identity")}
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
                  {t("profile.gender")}
                </label>
                <select
                  value={form.gender}
                  onChange={(e) => setForm({ ...form, gender: e.target.value })}
                  className="w-full rounded-xl border-2 border-gray-200 px-4 py-3 focus:border-emerald-500 focus:outline-none transition-all"
                >
                  <option value="">{t("profile.select_gender")}</option>
                  <option value="MALE">{t("profile.gender_male")}</option>
                  <option value="FEMALE">{t("profile.gender_female")}</option>
                  <option value="OTHER">{t("profile.gender_other")}</option>
                </select>
              </div>
            </div>
          </div>

          <div className="space-y-4 pt-6 border-t">
            <h3 className="text-lg font-semibold text-gray-700 flex items-center gap-2">
              <MapPin className="w-5 h-5 text-emerald-500" />
              {t("profile.section_address")}
            </h3>

            {oldAddress ? (
              <div className="grid grid-cols-1 gap-3">
                <label className="block text-sm font-medium text-gray-700">
                  {t("profile.current_address")}
                </label>
                <input
                  value={oldAddress}
                  readOnly
                  className="w-full rounded-xl border-2 border-gray-200 px-4 py-3 bg-gray-50 text-gray-700"
                />
              </div>
            ) : null}

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  {t("profile.province")}
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
                  placeholder={t("profile.select_province")}
                  searchPlaceholder={t("profile.search_placeholder")}
                  noOptionsText={t("profile.no_results")}
                  loading={false}
                  disabled={false}
                  renderIcon={<MapPin className="w-5 h-5" />}
                  debounceMs={250}
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  {t("profile.commune")}
                </label>
                <SearchableSelect
                  value={form.communeCode}
                  onChange={(val) => setForm({ ...form, communeCode: val })}
                  options={communeOptions}
                  placeholder={t("profile.select_commune")}
                  searchPlaceholder={t("profile.search_placeholder")}
                  noOptionsText={t("profile.no_results")}
                  loading={loadingCommune}
                  disabled={!form.provinceCode}
                  renderIcon={<MapPin className="w-5 h-5" />}
                  debounceMs={250}
                />
              </div>
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                {t("profile.house")}
              </label>
              <div className="relative">
                <Home className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                <input
                  value={form.house}
                  onChange={(e) => setForm({ ...form, house: e.target.value })}
                  placeholder={t("profile.placeholder_house")}
                  className="w-full rounded-xl border-2 border-gray-200 pl-10 pr-4 py-3 focus:border-emerald-500 focus:outline-none transition-all"
                />
              </div>
            </div>
          </div>

          <div className="flex items-center gap-4 justify-end pt-6 border-t">
            <button
              type="button"
              onClick={() => navigate("/profile")}
              className="px-6 py-3 rounded-xl border-2 border-gray-200 hover:border-gray-300 hover:bg-gray-50 transition-all font-medium"
            >
              {t("common.cancel")}
            </button>
            <button
              type="submit"
              disabled={submitting}
              className="px-8 py-3 rounded-xl text-white font-medium shadow-lg disabled:opacity-50 disabled:cursor-not-allowed transition-all bg-gradient-to-r from-emerald-500 to-sky-600 hover:from-sky-600 hover:to-emerald-500 flex items-center gap-2"
            >
              {submitting ? (
                <>
                  <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin" />
                  <span>{t("profile.saving")}</span>
                </>
              ) : (
                <>
                  <UserCheck className="w-5 h-5" />
                  <span>{t("profile.save_changes")}</span>
                </>
              )}
            </button>
          </div>
        </form>
      </div>
    </>
  );
}

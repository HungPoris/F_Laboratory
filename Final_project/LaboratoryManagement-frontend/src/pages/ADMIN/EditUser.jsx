import React, { useEffect, useMemo, useRef, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { useTranslation } from "react-i18next";
import Swal from "sweetalert2";
import { toast, ToastContainer } from "react-toastify";
import "react-toastify/dist/ReactToastify.css";
import http from "../../lib/api";
import { getAccessToken, clearSession } from "../../lib/auth";
import {
  fetchRoles,
  updateUser,
  fetchUserById,
  resetUserPassword,
} from "../../services/adminApi";
import {
  User,
  Mail,
  Phone,
  Calendar,
  CreditCard,
  MapPin,
  Home,
  UserCheck,
  Shield,
  Lock,
} from "lucide-react";

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

export default function EditUser() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const { id } = useParams();

  const [roles, setRoles] = useState([]);
  const [loadingRoles, setLoadingRoles] = useState(false);
  const [roleError, setRoleError] = useState(null);
  const [provinces, setProvinces] = useState([]);
  const [communes, setCommunes] = useState([]);
  const [loadingCommune, setLoadingCommune] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [loadingUser, setLoadingUser] = useState(true);

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
    roleCode: "",
    enabled: true,
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
          err?.response?.data?.message ||
          err?.message ||
          "Unable to load role list";
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
      .catch(() => {
        if (!mounted) return;
        setProvinces([]);
      });

    return () => (mounted = false);
  }, []);

  useEffect(() => {
    let mounted = true;
    setLoadingUser(true);
    fetchUserById(id)
      .then((u) => {
        if (!mounted) return;
        const roleCode =
          u?.roles?.[0]?.code ||
          u?.roles?.[0] ||
          u?.roleCode ||
          u?.primaryRole ||
          "";
        setForm((prev) => ({
          ...prev,
          username: u?.username || "",
          fullName: u?.fullName || "",
          email: u?.email || "",
          phoneNumber: u?.phoneNumber || "",
          dateOfBirth: u?.dateOfBirth || "",
          identityNumber: u?.identityNumber || "",
          gender:
            (u?.gender || "").toUpperCase() === "MALE"
              ? "MALE"
              : (u?.gender || "").toUpperCase() === "FEMALE"
              ? "FEMALE"
              : (u?.gender || "").toUpperCase() === "OTHER"
              ? "OTHER"
              : "",
          house: "",
          provinceCode: "",
          communeCode: "",
          roleCode: roleCode || "",
          enabled: u?.enabled !== false,
        }));
        setOldAddress(u?.address || "");
      })
      .catch((err) => {
        const msg =
          err?.response?.data?.message || err?.message || "User not found";
        Swal.fire("Error", msg, "error").then(() => navigate(-1));
      })
      .finally(() => setLoadingUser(false));
  }, [id, navigate]);

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
      })
      .finally(() => setLoadingCommune(false));
  }, [form.provinceCode]);

  function validate() {
    const e = {};

    const usernameRaw = String(form.username || "").trim();
    if (!usernameRaw || usernameRaw.length < 3) {
      e.username = "Username must be at least 3 characters long";
    } else if (!/^[a-zA-Z0-9._-]+$/.test(usernameRaw)) {
      e.username = "Username contains invalid characters";
    }

    const fullNameRaw = String(form.fullName || "").trim();
    const fullName = fullNameRaw.normalize("NFC");
    if (fullName.length < 2) {
      e.fullName = "Full name must be at least 2 characters long";
    } else if (!/^[\p{L}\s'.-]+$/u.test(fullName)) {
      e.fullName = "Full name cannot contain invalid characters";
    }

    const emailRaw = String(form.email || "").trim();
    const emailRegex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[A-Za-z]{2,}$/;
    if (!emailRaw || !emailRegex.test(emailRaw)) {
      e.email = "Invalid email address";
    }

    if (!form.roleCode) e.roleCode = "Role is required";

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
    return list.find((p) => p.code === code) || null;
  }

  function getCommuneByCode(code) {
    const list = Array.isArray(communes) ? communes : asArray(communes);
    return list.find((c) => c.code === code) || null;
  }

  function retryLoadRoles() {
    setLoadingRoles(true);
    setRoleError(null);
    fetchRoles()
      .then((r) => {
        const list = Array.isArray(r) ? r : r?.content || asArray(r);
        setRoles(list);
        setRoleError(null);
        toast.success("Roles reloaded successfully");
      })
      .catch((err) => {
        const errorMsg =
          err?.response?.data?.message ||
          err?.message ||
          "Unable to load roles";
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
        toast.error("Your session has expired. Please sign in again.");
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

      const fullNameRaw = String(form.fullName || "").trim();
      const fullName = fullNameRaw.normalize("NFC");
      const usernameRaw = String(form.username || "").trim();
      const emailRaw = String(form.email || "").trim();

      const payload = {
        username: usernameRaw,
        fullName: fullName,
        email: emailRaw,
        phoneNumber: form.phoneNumber || null,
        dateOfBirth: form.dateOfBirth || null,
        identityNumber: form.identityNumber || null,
        gender: genderDb,
        address: fullAddress || undefined,
        roles: form.roleCode ? [form.roleCode] : [],
        enabled: form.enabled !== false,
      };

      await updateUser(id, payload);
      toast.success("User updated successfully");
      await Swal.fire("Success", "User has been updated.", "success");
      navigate(-1);
    } catch (err) {
      const msg =
        err?.response?.data?.message || err?.message || "Failed to update user";
      Swal.fire("Error", msg, "error");
    } finally {
      setSubmitting(false);
    }
  }

  async function handleResetPassword() {
    const ok = await Swal.fire({
      title: "Reset password?",
      text: "A temporary password will be generated on the server and emailed to the user. They will be forced to change it on next login.",
      icon: "warning",
      showCancelButton: true,
      confirmButtonText: "Yes, reset",
      cancelButtonText: "Cancel",
      reverseButtons: true,
    });
    if (!ok.isConfirmed) return;
    try {
      await resetUserPassword(id);
      toast.success("Password reset and email sent.");
    } catch (e) {
      const msg =
        e?.response?.data?.message || e?.message || "Failed to reset password";
      toast.error(msg);
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

  if (loadingUser) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="w-10 h-10 border-2 border-gray-300 border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

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
                  {t("admin.edit_user", "Edit User")}
                </h1>
                <p className="text-sm text-gray-500 mt-1">
                  Update user information
                </p>
              </div>
            </div>

            <form onSubmit={onSubmit} className="space-y-6">
              <div className="space-y-4">
                <h3 className="text-lg font-semibold text-gray-700 flex items-center gap-2">
                  <User className="w-5 h-5 text-emerald-500" />
                  Login Information
                </h3>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      Username <span className="text-red-500">*</span>
                    </label>
                    <div className="relative">
                      <User className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                      <input
                        value={form.username}
                        readOnly
                        disabled
                        className="w-full rounded-xl border-2 border-gray-200 pl-10 pr-4 py-3 bg-gray-50 text-gray-600 cursor-not-allowed"
                      />
                    </div>
                    {errors.username && (
                      <div className="text-sm text-red-600 mt-1">
                        {errors.username}
                      </div>
                    )}
                  </div>

                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      Full Name <span className="text-red-500">*</span>
                    </label>
                    <div className="relative">
                      <User className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                      <input
                        value={form.fullName}
                        onChange={(e) =>
                          setForm({ ...form, fullName: e.target.value })
                        }
                        placeholder="Enter full name"
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
                    Email <span className="text-red-500">*</span>
                  </label>
                  <div className="relative">
                    <Mail className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                    <input
                      type="email"
                      value={form.email}
                      onChange={(e) =>
                        setForm({ ...form, email: e.target.value })
                      }
                      placeholder="email@example.com"
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
                  Personal Information
                </h3>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      Phone Number
                    </label>
                    <div className="relative">
                      <Phone className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                      <input
                        value={form.phoneNumber}
                        onChange={(e) =>
                          setForm({ ...form, phoneNumber: e.target.value })
                        }
                        placeholder="0123456789"
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
                      Date of Birth
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
                      Citizen ID / Passport Number
                    </label>
                    <div className="relative">
                      <CreditCard className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                      <input
                        value={form.identityNumber}
                        onChange={(e) =>
                          setForm({ ...form, identityNumber: e.target.value })
                        }
                        placeholder="Citizen ID / Passport Number"
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
                      Gender
                    </label>
                    <select
                      value={form.gender}
                      onChange={(e) =>
                        setForm({ ...form, gender: e.target.value })
                      }
                      className="w-full rounded-xl border-2 border-gray-200 px-4 py-3 focus:border-emerald-500 focus:outline-none transition-all"
                    >
                      <option value="">-- Select gender --</option>
                      <option value="MALE">Male</option>
                      <option value="FEMALE">Female</option>
                      <option value="OTHER">Other</option>
                    </select>
                  </div>
                </div>
              </div>

              <div className="space-y-4 pt-6 border-t">
                <h3 className="text-lg font-semibold text-gray-700 flex items-center gap-2">
                  <MapPin className="w-5 h-5 text-emerald-500" />
                  Address
                </h3>

                {oldAddress ? (
                  <div className="grid grid-cols-1 gap-3">
                    <label className="block text-sm font-medium text-gray-700">
                      Current Address
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
                      Province/City
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
                      placeholder="-- Select province/city --"
                      searchPlaceholder="Type to search..."
                      noOptionsText="No results"
                      loading={false}
                      disabled={false}
                      renderIcon={<MapPin className="w-5 h-5" />}
                      debounceMs={250}
                    />
                  </div>

                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      Ward/Commune/Town
                    </label>
                    <SearchableSelect
                      value={form.communeCode}
                      onChange={(val) => setForm({ ...form, communeCode: val })}
                      options={communeOptions}
                      placeholder={
                        form.provinceCode
                          ? "-- Select ward/commune --"
                          : "-- Select ward/commune --"
                      }
                      searchPlaceholder="Type to search..."
                      noOptionsText="No results"
                      loading={loadingCommune}
                      disabled={!form.provinceCode}
                      renderIcon={<MapPin className="w-5 h-5" />}
                      debounceMs={250}
                    />
                  </div>
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    House number, street
                  </label>
                  <div className="relative">
                    <Home className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                    <input
                      value={form.house}
                      onChange={(e) =>
                        setForm({ ...form, house: e.target.value })
                      }
                      placeholder="House number, street, lane..."
                      className="w-full rounded-xl border-2 border-gray-200 pl-10 pr-4 py-3 focus:border-emerald-500 focus:outline-none transition-all"
                    />
                  </div>
                </div>
              </div>

              <div className="space-y-4 pt-6 border-t">
                <h3 className="text-lg font-semibold text-gray-700 flex items-center gap-2">
                  <Shield className="w-5 h-5 text-emerald-500" />
                  Roles & Security
                </h3>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    Role <span className="text-red-500">*</span>
                  </label>
                  {loadingRoles ? (
                    <div className="flex items-center justify-center p-6 border-2 border-dashed rounded-xl bg-gray-50">
                      <div className="text-sm text-gray-600">
                        Loading roles...
                      </div>
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
                        Retry
                      </button>
                    </div>
                  ) : roles.length === 0 ? (
                    <div className="p-4 border-2 border-yellow-200 rounded-xl bg-yellow-50">
                      <div className="text-sm text-yellow-700 mb-3">
                        No roles available
                      </div>
                      <button
                        type="button"
                        onClick={retryLoadRoles}
                        className="text-sm px-4 py-2 rounded-lg bg-yellow-600 text-white hover:bg-yellow-700 transition"
                      >
                        Reload
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
                      <option value="">-- Select role --</option>
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

                <div className="flex items-end">
                  <button
                    type="button"
                    onClick={handleResetPassword}
                    className="h-12 px-6 rounded-xl text-white font-medium shadow-lg hover:shadow-xl transition-all bg-gradient-to-r from-rose-500 to-red-600 hover:from-red-600 hover:to-rose-600 flex items-center justify-center gap-2"
                  >
                    <Lock className="w-5 h-5" />
                    <span>Reset password</span>
                  </button>
                </div>
              </div>

              <div className="flex items-center gap-4 justify-end pt-6 border-t">
                <button
                  type="button"
                  onClick={() => navigate(-1)}
                  className="px-6 py-3 rounded-xl border-2 border-gray-200 hover:border-gray-300 hover:bg-gray-50 transition-all font-medium"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={submitting}
                  className="px-8 py-3 rounded-xl text-white font-medium shadow-lg disabled:opacity-50 disabled:cursor-not-allowed transition-all bg-gradient-to-r from-emerald-500 to-sky-600 hover:from-sky-600 hover:to-emerald-500 flex items-center gap-2"
                >
                  {submitting ? (
                    <>
                      <div className="w-5 h-5 border-2 border-white border-t-transparent rounded-full animate-spin" />
                      <span>Saving...</span>
                    </>
                  ) : (
                    <>
                      <UserCheck className="w-5 h-5" />
                      <span>Save Changes</span>
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

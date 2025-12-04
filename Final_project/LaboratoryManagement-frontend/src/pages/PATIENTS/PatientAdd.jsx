/* eslint-disable */
import React, { useState, useEffect, useMemo, useRef } from "react";
import { useNavigate } from "react-router-dom";
import axios from "axios";
import Swal from "sweetalert2";
import {
  User,
  Mail,
  Phone,
  Calendar,
  MapPin,
  UserPlus,
  ArrowLeft,
  Home,
} from "lucide-react";

// Import thư viện gọi API chung để lấy Address
import http from "../../lib/api";
import Loading from "../../components/Loading"; // nếu chưa dùng có thể xoá

const PATIENT_API_BASE =
  import.meta.env.VITE_API_TESTORDER_PATIENT || "https://be2.flaboratory.cloud";

// --- CÁC HÀM & COMPONENT HỖ TRỢ ---

function unaccent(input = "") {
  return String(input)
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/đ/g, "d")
    .replace(/Đ/g, "D");
}

function cleanAddress(input = "") {
  return String(input)
    .replace(/\s+/g, " ")
    .replace(/[\r\n\t]+/g, " ")
    .trim();
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
        <div className="absolute z-50 mt-2 w-full rounded-xl border-2 border-emerald-200 bg-white shadow-xl">
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

// --- MAIN COMPONENT ---

export default function PatientAdd() {
  const navigate = useNavigate();

  const [formData, setFormData] = useState({
    fullName: "",
    dateOfBirth: "",
    gender: "MALE",
    phoneNumber: "",
    email: "",
    provinceCode: "",
    communeCode: "",
    houseNumber: "",
  });

  const [provinces, setProvinces] = useState([]);
  const [communes, setCommunes] = useState([]);
  const [loadingCommune, setLoadingCommune] = useState(false);
  const [errors, setErrors] = useState({});

  // Helper xử lý dữ liệu mảng trả về từ API
  function asArray(raw) {
    if (Array.isArray(raw)) return raw;
    if (Array.isArray(raw?.content)) return raw.content;
    if (Array.isArray(raw?.data)) return raw.data;
    if (Array.isArray(raw?.items)) return raw.items;
    if (Array.isArray(raw?.results)) return raw.results;
    if (raw && typeof raw === "object") return Object.values(raw);
    return [];
  }

  // --- API LOAD PROVINCES ---
  useEffect(() => {
    let mounted = true;
    http
      .get("/api/v1/addresses/provinces")
      .then((res) => {
        if (!mounted) return;
        const data = asArray(res?.data?.provinces ?? res?.data);
        setProvinces(data);
      })
      .catch((err) => {
        if (!mounted) return;
        console.error("Failed to load provinces", err);
        setProvinces([]);
      });
    return () => (mounted = false);
  }, []);

  // --- API LOAD COMMUNES KHI CHỌN TỈNH ---
  useEffect(() => {
    const { provinceCode } = formData;
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
        console.error("Failed to load communes", err);
        setCommunes([]);
      })
      .finally(() => setLoadingCommune(false));
  }, [formData.provinceCode]);

  // Helpers format tên + phone
  const cleanNameTyping = (value) => value;
  const finalizeName = (value) => {
    const lettersOnly = /^[\p{L}\s'.-]+$/u;
    if (!lettersOnly.test(value.trim())) return value;
    return value
      .trim()
      .replace(/\s+/g, " ")
      .split(" ")
      .map((w) => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase())
      .join(" ");
  };

  const formatPhone = (value) => value.replace(/\D/g, "");

  // ================== VALIDATE (bắt lỗi như bạn yêu cầu) ==================
  const validateForm = () => {
    const newErrors = {};

    // Full Name: required + chỉ chữ (có dấu), khoảng trắng, '.-
    if (!formData.fullName.trim()) {
      newErrors.fullName = "Full name is required";
    } else if (!/^[\p{L}\s'.-]+$/u.test(formData.fullName.trim())) {
      newErrors.fullName = "Full name must contain only letters";
    }

    // DOB required
    if (!formData.dateOfBirth) {
      newErrors.dateOfBirth = "Date of birth is required";
    }

    // Phone: required, chỉ số, 10 số, bắt đầu bằng 0
    const phone = formData.phoneNumber.trim();
    if (!phone) {
      newErrors.phoneNumber = "Phone number is required";
    } else if (!/^\d{10}$/.test(phone)) {
      newErrors.phoneNumber = "Phone number must be exactly 10 digits";
    } else if (!/^0\d{9}$/.test(phone)) {
      newErrors.phoneNumber = "Phone number must start with 0";
    }

    // Email: optional nhưng nếu có thì đúng format
    if (formData.email.trim() !== "") {
      const emailRegex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[A-Za-z]{2,}$/;
      if (!emailRegex.test(formData.email.trim())) {
        newErrors.email = "Invalid email format";
      }
    }

    // Province / Commune required
    if (!formData.provinceCode) {
      newErrors.provinceCode = "Province is required";
    }
    if (!formData.communeCode) {
      newErrors.communeCode = "Commune/Ward is required";
    }

    // House Number: required + chỉ chữ (có dấu), số, khoảng trắng
    if (!formData.houseNumber.trim()) {
      newErrors.houseNumber = "House number/Street is required";
    } else if (!/^[0-9A-Za-zÀ-ỹ\s,\.]+$/u.test(formData.houseNumber.trim())) {
      newErrors.houseNumber =
        "House number can contain letters, numbers, commas or dots only";
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleChange = (e) => {
    const { name, value } = e.target;
    let v = value;
    if (name === "fullName") v = cleanNameTyping(v);
    if (name === "phoneNumber") v = formatPhone(v); // chỉ số
    // houseNumber cho gõ tự do, chỉ validate khi submit
    setFormData((prev) => ({ ...prev, [name]: v }));
    setErrors((prev) => ({ ...prev, [name]: "" }));
  };

  // Helpers tìm tên từ code
  function getProvinceByCode(code) {
    const list = Array.isArray(provinces) ? provinces : asArray(provinces);
    return list.find((p) => String(p.code) === String(code)) || null;
  }
  function getCommuneByCode(code) {
    const list = Array.isArray(communes) ? communes : asArray(communes);
    return list.find((c) => String(c.code) === String(code)) || null;
  }

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!validateForm()) return;

    // --- Ghép địa chỉ ---
    const prov = getProvinceByCode(formData.provinceCode);
    const comm = getCommuneByCode(formData.communeCode);
    const cleanedHouse = cleanAddress(formData.houseNumber || "");

    const addressParts = [];
    if (cleanedHouse) addressParts.push(cleanedHouse);
    if (comm && comm.name) addressParts.push(comm.name);
    if (prov && prov.name) addressParts.push(prov.name);
    const fullAddress = addressParts.join(", ");

    const token = localStorage.getItem("lm.access");
    const payload = {
      fullName: formData.fullName,
      dob: formData.dateOfBirth,
      gender: formData.gender,
      contactNumber: formData.phoneNumber,
      email: formData.email,
      address: fullAddress,
    };

    try {
      await axios.post(`${PATIENT_API_BASE}/api/v1/patients`, payload, {
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
      });

      Swal.fire({
        icon: "success",
        title: "Patient created!",
        timer: 1500,
      });

      navigate("/patients");
    } catch (error) {
      Swal.fire({
        icon: "error",
        title: "Error",
        text: error.response?.data?.message || "Failed to create patient",
      });
    }
  };

  // Prepare options for Select
  const provinceOptions = provinces.map((p) => ({
    value: p.code,
    label: p.name,
  }));
  const communeOptions = communes.map((c) => ({
    value: c.code,
    label: c.name,
  }));

  return (
    <>
      <style>{`
        @keyframes fade-in {
          from { opacity: 0; transform: translateY(10px); }
          to { opacity: 1; transform: translateY(0); }
        }
        .fade-in { animation: fade-in 0.5s ease-out; }
      `}</style>

      <div className="min-h-screen bg-gradient-to-br from-emerald-50 via-sky-50 to-indigo-50 p-6">
        <div className="w-full mx-auto">
          <button
            onClick={() => navigate("/patients")}
            className="inline-flex items-center gap-2 text-gray-600 hover:text-emerald-600 font-medium mb-6 transition-colors"
          >
            <ArrowLeft className="w-5 h-5" />
            Back to Patients
          </button>

          <div className="bg-white rounded-3xl shadow-xl p-8 fade-in">
            <div className="flex items-center gap-3 mb-8">
              <div className="p-3 rounded-2xl bg-gradient-to-br from-emerald-500 to-sky-600">
                <UserPlus className="w-8 h-8 text-white" />
              </div>
              <div>
                <h1 className="text-3xl font-bold bg-gradient-to-r from-emerald-600 to-sky-600 bg-clip-text text-transparent">
                  Add New Patient
                </h1>
                <p className="text-sm text-gray-500 mt-1">
                  Fill in the patient information below
                </p>
              </div>
            </div>

            <form onSubmit={handleSubmit} className="space-y-6">
              {/* PERSONAL INFO */}
              <div className="space-y-4">
                <h3 className="text-lg font-semibold text-gray-700 flex items-center gap-2">
                  <User className="w-5 h-5 text-emerald-500" />
                  Personal Information
                </h3>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      Full Name <span className="text-red-500">*</span>
                    </label>
                    <div className="relative">
                      <User className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                      <input
                        type="text"
                        name="fullName"
                        value={formData.fullName}
                        onChange={handleChange}
                        onBlur={() =>
                          setFormData((prev) => ({
                            ...prev,
                            fullName: finalizeName(prev.fullName),
                          }))
                        }
                        autoComplete="off"
                        placeholder="Enter patient's full name"
                        className="w-full rounded-xl border-2 border-gray-200 pl-10 pr-4 py-3 focus:border-emerald-500 focus:outline-none"
                      />
                    </div>
                    {errors.fullName && (
                      <p className="text-red-500 text-sm mt-1">
                        {errors.fullName}
                      </p>
                    )}
                  </div>

                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      Date of Birth <span className="text-red-500">*</span>
                    </label>
                    <div className="relative">
                      <Calendar className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                      <input
                        type="date"
                        name="dateOfBirth"
                        value={formData.dateOfBirth}
                        onChange={handleChange}
                        max={new Date().toISOString().split("T")[0]}
                        className="w-full rounded-xl border-2 border-gray-200 pl-10 pr-4 py-3 focus:border-emerald-500 focus:outline-none"
                      />
                    </div>
                    {errors.dateOfBirth && (
                      <p className="text-red-500 text-sm mt-1">
                        {errors.dateOfBirth}
                      </p>
                    )}
                  </div>
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    Gender
                  </label>
                  <select
                    name="gender"
                    value={formData.gender}
                    onChange={handleChange}
                    className="w-full rounded-xl border-2 border-gray-200 px-4 py-3 focus:border-emerald-500 focus:outline-none"
                  >
                    <option value="MALE">Male</option>
                    <option value="FEMALE">Female</option>
                    <option value="OTHER">Other</option>
                  </select>
                </div>
              </div>

              {/* CONTACT INFO */}
              <div className="space-y-4 pt-6 border-t">
                <h3 className="text-lg font-semibold text-gray-700 flex items-center gap-2">
                  <Phone className="w-5 h-5 text-sky-500" />
                  Contact Information
                </h3>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      Phone Number <span className="text-red-500">*</span>
                    </label>
                    <div className="relative">
                      <Phone className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                      <input
                        type="text"
                        name="phoneNumber"
                        value={formData.phoneNumber}
                        onChange={handleChange}
                        placeholder="Enter phone number"
                        className="w-full rounded-xl border-2 border-gray-200 pl-10 pr-4 py-3 focus:border-emerald-500 focus:outline-none"
                      />
                    </div>
                    {errors.phoneNumber && (
                      <p className="text-red-500 text-sm mt-1">
                        {errors.phoneNumber}
                      </p>
                    )}
                  </div>

                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      Email
                    </label>
                    <div className="relative">
                      <Mail className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                      <input
                        type="email"
                        name="email"
                        value={formData.email}
                        onChange={handleChange}
                        placeholder="Enter email"
                        className="w-full rounded-xl border-2 border-gray-200 pl-10 pr-4 py-3 focus:border-emerald-500 focus:outline-none"
                      />
                    </div>
                    {errors.email && (
                      <p className="text-red-500 text-sm mt-1">
                        {errors.email}
                      </p>
                    )}
                  </div>
                </div>
              </div>

              {/* ADDRESS INFO */}
              <div className="space-y-4 pt-6 border-t">
                <h3 className="text-lg font-semibold text-gray-700 flex items-center gap-2">
                  <MapPin className="w-5 h-5 text-emerald-500" />
                  Address Information
                </h3>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                  {/* Province */}
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      Province / City <span className="text-red-500">*</span>
                    </label>
                    <SearchableSelect
                      value={formData.provinceCode}
                      onChange={(val) =>
                        setFormData((prev) => ({
                          ...prev,
                          provinceCode: val,
                          communeCode: "",
                        }))
                      }
                      options={provinceOptions}
                      placeholder="Select Province"
                      searchPlaceholder="Search province..."
                      noOptionsText="No results"
                      loading={false}
                      disabled={false}
                      renderIcon={<MapPin className="w-5 h-5" />}
                      debounceMs={250}
                    />
                    {errors.provinceCode && (
                      <p className="text-red-500 text-sm mt-1">
                        {errors.provinceCode}
                      </p>
                    )}
                  </div>

                  {/* Commune */}
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      Commune / Ward <span className="text-red-500">*</span>
                    </label>
                    <SearchableSelect
                      value={formData.communeCode}
                      onChange={(val) =>
                        setFormData((prev) => ({ ...prev, communeCode: val }))
                      }
                      options={communeOptions}
                      placeholder="Select Commune"
                      searchPlaceholder="Search commune..."
                      noOptionsText="No results"
                      loading={loadingCommune}
                      disabled={!formData.provinceCode}
                      renderIcon={<MapPin className="w-5 h-5" />}
                      debounceMs={250}
                    />
                    {errors.communeCode && (
                      <p className="text-red-500 text-sm mt-1">
                        {errors.communeCode}
                      </p>
                    )}
                  </div>
                </div>

                {/* House Number */}
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    House Number / Street{" "}
                    <span className="text-red-500">*</span>
                  </label>
                  <div className="relative">
                    <Home className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                    <input
                      name="houseNumber"
                      value={formData.houseNumber}
                      onChange={handleChange}
                      placeholder="Enter house number, street name..."
                      className="w-full rounded-xl border-2 border-gray-200 pl-10 pr-4 py-3 focus:border-emerald-500 focus:outline-none"
                    />
                  </div>
                  {errors.houseNumber && (
                    <p className="text-red-500 text-sm mt-1">
                      {errors.houseNumber}
                    </p>
                  )}
                </div>
              </div>

              {/* BUTTONS */}
              <div className="flex justify-end gap-4 pt-6 border-t">
                <button
                  type="button"
                  onClick={() => navigate("/patients")}
                  className="px-6 py-3 rounded-xl border-2 border-gray-200 hover:border-gray-300 hover:bg-gray-50 transition-all"
                >
                  Cancel
                </button>

                <button
                  type="submit"
                  className="px-8 py-3 rounded-xl text-white font-medium shadow-lg bg-gradient-to-r from-emerald-500 to-sky-600 hover:from-sky-600 hover:to-emerald-500 flex items-center gap-2"
                >
                  <UserPlus className="w-5 h-5" />
                  Create Patient
                </button>
              </div>
            </form>
          </div>
        </div>
      </div>
    </>
  );
}

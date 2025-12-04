/* eslint-disable no-case-declarations */
/* eslint-disable no-unused-vars */

import React, { useState, useEffect } from "react";
import { Link, useNavigate } from "react-router-dom";
import axios from "axios";
import { useDebounce } from "../../hooks/useDebounce";
import PaginationControls from "../../components/PaginationControls";
import {
  Users,
  UserCheck,
  UserX,
  Search,
  Filter,
  Plus,
  Edit3,
  Eye,
  Trash2,
  X,
  CheckCircle2,
  AlertCircle,
  Info,
  Loader2,
} from "lucide-react";

const PATIENT_API_BASE =
  import.meta.env.VITE_API_TESTORDER_PATIENT || "https://be2.flaboratory.cloud";

/* ----------------------------------- TOAST ----------------------------------- */
function Toast({ message, type = "success", onClose }) {
  useEffect(() => {
    const timer = setTimeout(onClose, 4000);
    return () => clearTimeout(timer);
  }, [onClose]);

  const icons = {
    success: <CheckCircle2 className="w-5 h-5" />,
    error: <AlertCircle className="w-5 h-5" />,
    info: <Info className="w-5 h-5" />,
  };

  const styles = {
    success: "from-emerald-500 to-teal-500 shadow-emerald-500/30",
    error: "from-red-500 to-pink-500 shadow-red-500/30",
    info: "from-blue-500 to-indigo-500 shadow-blue-500/30",
  };

  return (
    <div className="fixed top-6 right-6 z-50 animate-slideIn">
      <div
        className={`bg-gradient-to-r ${styles[type]} text-white px-6 py-4 rounded-2xl shadow-2xl flex items-center gap-3 min-w-[320px]`}
      >
        {icons[type]}
        <span className="flex-1 font-medium">{message}</span>
        <button
          onClick={onClose}
          className="hover:bg-white/20 p-1 rounded-lg transition-colors"
        >
          <X className="w-4 h-4" />
        </button>
      </div>
    </div>
  );
}

/* ---------------------------------- ALERT ---------------------------------- */
function SweetAlert({ title, text, type = "warning", onConfirm, onCancel }) {
  const icons = {
    warning: <AlertCircle className="w-16 h-16 text-orange-500" />,
    danger: <AlertCircle className="w-16 h-16 text-red-500" />,
    question: <Info className="w-16 h-16 text-blue-500" />,
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm animate-fadeIn">
      <div className="bg-white rounded-3xl shadow-2xl p-8 max-w-md w-full mx-4 animate-scaleIn">
        <div className="flex flex-col items-center text-center gap-4">
          {icons[type]}
          <h3 className="text-2xl font-bold text-gray-900">{title}</h3>
          <p className="text-gray-600">{text}</p>
          <div className="flex gap-3 mt-4 w-full">
            <button
              onClick={onCancel}
              className="flex-1 px-6 py-3 rounded-xl border-2 border-gray-200 hover:bg-gray-50 font-semibold text-gray-700 transition-all duration-200"
            >
              Cancel
            </button>
            <button
              onClick={onConfirm}
              className="flex-1 px-6 py-3 rounded-xl bg-gradient-to-r from-red-500 to-pink-500 hover:from-red-600 hover:to-pink-600 text-white font-semibold shadow-lg shadow-red-500/30 hover:shadow-red-500/50 transition-all duration-200"
            >
              Confirm
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

/* ---------------------------------- AVATAR ---------------------------------- */
function Avatar({ name = "", gender = "" }) {
  const initials = (name || "P").slice(0, 2).toUpperCase();
  const colors = {
    male: "from-blue-400 to-blue-600",
    female: "from-pink-400 to-pink-600",
    default: "from-purple-400 to-purple-600",
  };

  const colorClass =
    gender?.toLowerCase() === "male"
      ? colors.male
      : gender?.toLowerCase() === "female"
      ? colors.female
      : colors.default;

  return (
    <div
      className={`w-11 h-11 rounded-xl bg-gradient-to-br ${colorClass} flex items-center justify-center text-white font-bold shadow-lg`}
    >
      {initials}
    </div>
  );
}

/* ------------------------ FILTER MODAL (TỪ CODE CŨ) ------------------------ */
function FilterModal({ open, onClose, onApply, initial }) {
  const FIELD_OPTIONS = [
    { value: "name", label: "Name", type: "text" },
    { value: "phone", label: "Phone", type: "text" },
    { value: "email", label: "Email", type: "text" },
    { value: "gender", label: "Gender", type: "gender" },
    { value: "dob", label: "DOB", type: "date" },
  ];

  const OPERATORS = {
    text: [
      { value: "contains", label: "contains" },
      { value: "equals", label: "equals" },
      { value: "starts", label: "starts with" },
      { value: "ends", label: "ends with" },
    ],
    gender: [
      { value: "is", label: "is" },
      { value: "is_not", label: "is not" },
    ],
    date: [
      { value: "is", label: "is" },
      { value: "before", label: "before" },
      { value: "after", label: "after" },
      { value: "between", label: "between" },
    ],
  };

  const DEFAULT_FILTER = {
    field: "name",
    operator: "contains",
    value: "",
    value2: "",
  };

  const [filters, setFilters] = useState(initial?.filters || [DEFAULT_FILTER]);

  const handleFieldChange = (index, newField) => {
    const fieldType = FIELD_OPTIONS.find((f) => f.value === newField).type;

    setFilters((prev) =>
      prev.map((f, i) =>
        i === index
          ? {
              ...f,
              field: newField,
              operator: OPERATORS[fieldType][0].value,
              value: "",
              value2: "",
            }
          : f
      )
    );
  };

  const handleOperatorChange = (index, newOperator) => {
    setFilters((prev) =>
      prev.map((f, i) => (i === index ? { ...f, operator: newOperator } : f))
    );
  };

  const handleValueChange = (index, fieldName, newValue) => {
    setFilters((prev) =>
      prev.map((f, i) => (i === index ? { ...f, [fieldName]: newValue } : f))
    );
  };

  const addFilter = () => {
    setFilters([...filters, { ...DEFAULT_FILTER }]);
  };

  const removeFilter = (index) => {
    setFilters(filters.filter((_, i) => i !== index));
  };

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 animate-fadeIn p-4">
      <div className="bg-white rounded-3xl shadow-2xl w-full max-w-xl p-6 animate-scaleIn">
        {/* Header */}
        <div className="flex items-center justify-between mb-6">
          <h2 className="text-xl font-bold text-gray-900">Filter</h2>
          <button
            onClick={onClose}
            className="p-2 rounded-lg hover:bg-gray-100"
          >
            <X className="w-5 h-5 text-gray-500" />
          </button>
        </div>

        {/* Filter Builder */}
        <div className="space-y-5">
          {filters.map((f, index) => {
            const fieldType = FIELD_OPTIONS.find(
              (x) => x.value === f.field
            ).type;

            return (
              <div key={index} className="grid grid-cols-12 gap-3 items-center">
                {/* FIELD */}
                <div className="col-span-4">
                  <select
                    value={f.field}
                    onChange={(e) => handleFieldChange(index, e.target.value)}
                    className="w-full p-3 rounded-xl border focus:ring-2"
                  >
                    {FIELD_OPTIONS.map((o) => (
                      <option key={o.value} value={o.value}>
                        {o.label}
                      </option>
                    ))}
                  </select>
                </div>

                {/* OPERATOR */}
                <div className="col-span-4">
                  <select
                    value={f.operator}
                    onChange={(e) =>
                      handleOperatorChange(index, e.target.value)
                    }
                    className="w-full p-3 rounded-xl border focus:ring-2"
                  >
                    {OPERATORS[fieldType].map((op) => (
                      <option key={op.value} value={op.value}>
                        {op.label}
                      </option>
                    ))}
                  </select>
                </div>

                {/* VALUE */}
                <div className="col-span-3">
                  {fieldType === "gender" ? (
                    <select
                      value={f.value}
                      onChange={(e) =>
                        handleValueChange(index, "value", e.target.value)
                      }
                      className="w-full p-3 rounded-xl border"
                    >
                      <option value="">Select</option>
                      <option value="male">Male</option>
                      <option value="female">Female</option>
                    </select>
                  ) : fieldType === "date" && f.operator === "between" ? (
                    <div className="flex gap-2">
                      <input
                        type="date"
                        value={f.value}
                        onChange={(e) =>
                          handleValueChange(index, "value", e.target.value)
                        }
                        className="p-2 rounded-lg border w-full"
                      />
                      <input
                        type="date"
                        value={f.value2}
                        onChange={(e) =>
                          handleValueChange(index, "value2", e.target.value)
                        }
                        className="p-2 rounded-lg border w-full"
                      />
                    </div>
                  ) : fieldType === "date" ? (
                    <input
                      type="date"
                      value={f.value}
                      onChange={(e) =>
                        handleValueChange(index, "value", e.target.value)
                      }
                      className="w-full p-3 rounded-xl border"
                    />
                  ) : (
                    <input
                      type="text"
                      value={f.value}
                      onChange={(e) =>
                        handleValueChange(index, "value", e.target.value)
                      }
                      className="w-full p-3 rounded-xl border"
                      placeholder="Enter value..."
                    />
                  )}
                </div>

                {/* REMOVE */}
                <div className="col-span-1 flex items-center justify-center">
                  {filters.length > 1 && (
                    <button
                      onClick={() => removeFilter(index)}
                      className="p-2 hover:bg-gray-100 rounded-full"
                    >
                      <X className="w-5 h-5 text-gray-400" />
                    </button>
                  )}
                </div>
              </div>
            );
          })}
        </div>

        {/* Add Filter + Clear All */}
        <div className="flex items-center justify-between mt-5">
          {/* Add Filter */}
          <button
            onClick={addFilter}
            className="flex items-center gap-2 text-blue-600 font-medium"
          >
            <Plus className="w-5 h-5" />
            Add filter
          </button>

          {/* Clear All */}
          <button
            onClick={() => setFilters([{ ...DEFAULT_FILTER }])}
            className="text-red-500 font-medium hover:underline"
          >
            Clear all
          </button>
        </div>

        {/* Footer */}
        <div className="flex justify-end gap-3 mt-6">
          <button onClick={onClose} className="px-4 py-2 rounded-xl border">
            Cancel
          </button>

          <button
            onClick={() => onApply({ filters })}
            className="px-6 py-2 rounded-xl bg-gradient-to-r from-teal-500 to-emerald-500 text-white"
          >
            Apply
          </button>
        </div>
      </div>
    </div>
  );
}

/* ========================= PATIENT LIST COMPONENT ========================= */
export default function PatientList() {
  const navigate = useNavigate();

  const [patients, setPatients] = useState([]);
  const [loading, setLoading] = useState(true);
  const [isSearching, setIsSearching] = useState(false);
  const [error, setError] = useState(null);

  const [searchTerm, setSearchTerm] = useState("");
  const debouncedSearchTerm = useDebounce(searchTerm, 500);

  /* Pagination */
  const [currentPage, setCurrentPage] = useState(1);
  const [pageSize, setPageSize] = useState(10);
  const [totalPages, setTotalPages] = useState(1);
  const [totalElements, setTotalElements] = useState(0);

  /* Toast & Alert */
  const [toast, setToast] = useState(null);
  const [alert, setAlert] = useState(null);

  /* Filter Modal state (từ code cũ) */
  const [filterOpen, setFilterOpen] = useState(false);
  const [appliedFilters, setAppliedFilters] = useState({
    filters: [],
  });

  /* 📊 STATS STATE (code mới) */
  const [stats, setStats] = useState({
    total: 0,
    male: 0,
    female: 0,
  });

  const showToast = (message, type = "success") => {
    setToast({ message, type });
  };

  /* BUILD PARAMS – merge code mới + filter cũ */
  const buildParams = (filters, page, size) => {
    const params = {
      page: page - 1,
      size: size, // ✅ THÊM DÒNG NÀY
    };

    // Áp dụng filter từ FilterModal cũ
    if (filters?.filters) {
      filters.filters.forEach((f) => {
        if (!f.value) return;

        if (f.field === "name") params.name = f.value;
        if (f.field === "phone") params.phone = f.value;
        if (f.field === "email") params.email = f.value;
        if (f.field === "gender") params.gender = f.value;

        if (f.field === "dob") {
          params.dob = f.value;
          params.dobOperator = f.operator;
          if (f.operator === "between") {
            params.dobTo = f.value2;
          }
        }
      });
    }

    return params;
  };

  /* LOAD PATIENTS (DANH SÁCH) */
  const loadPatients = async (query = "", isInitialLoad = false) => {
    try {
      if (isInitialLoad) setLoading(true);
      else setIsSearching(true);

      setError(null);

      const token = localStorage.getItem("lm.access");
      const url = `${PATIENT_API_BASE}/api/v1/patients`;

      const params = buildParams(appliedFilters, currentPage, pageSize);

      // Quick search bar override name
      if (query && query.trim() !== "") {
        params.name = query.trim();
      }

      const response = await axios.get(url, {
        headers: { Authorization: `Bearer ${token}` },
        params,
      });

      const data = response.data;

      setPatients(data.items || []);
      setTotalPages(data.totalPages || 1);
      setTotalElements(data.totalElements || 0);
    } catch (err) {
      console.error("Failed to load patients:", err);
      setError("Failed to load patients");
      showToast("Failed to load patients", "error");
    } finally {
      setLoading(false);
      setIsSearching(false);
    }
  };

  /* LOAD STATS (code mới, gọi /stats) */
  const loadStats = async () => {
    try {
      const token = localStorage.getItem("lm.access");
      const url = `${PATIENT_API_BASE}/api/v1/patients/stats`;

      const res = await axios.get(url, {
        headers: { Authorization: `Bearer ${token}` },
      });

      setStats({
        total: res.data.total || 0,
        male: res.data.male || 0,
        female: res.data.female || 0,
      });
    } catch (err) {
      console.error("Failed to load stats:", err);
      // Không show toast lỗi để tránh phiền người dùng
    }
  };

  /* USE EFFECT LOAD (search + paging + filter) */
  useEffect(() => {
    loadPatients(debouncedSearchTerm, patients.length === 0);
    loadStats();
  }, [debouncedSearchTerm, currentPage, pageSize, appliedFilters]); // ✅ THÊM pageSize VÀO ĐÂY

  /* DELETE HANDLER */
  const handleDelete = (patient) => {
    setAlert({
      title: "Delete Patient?",
      text: `Are you sure you want to delete ${patient.fullName}?`,
      type: "danger",
      onConfirm: () => {
        setAlert(null);
        axios
          .delete(`${PATIENT_API_BASE}/api/v1/patients/${patient.patientId}`, {
            headers: {
              Authorization: `Bearer ${localStorage.getItem("lm.access")}`,
            },
          })
          .then(() => {
            showToast("Patient deleted successfully", "success");
            loadPatients(debouncedSearchTerm);
            loadStats();
          })
          .catch(() => showToast("Failed to delete patient", "error"));
      },
      onCancel: () => setAlert(null),
    });
  };

  const startIndex = (currentPage - 1) * pageSize;

  /* LOADING SCREEN */
  if (loading && patients.length === 0) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-gradient-to-br from-gray-50 to-gray-100">
        <div className="text-center">
          <div className="inline-block animate-spin rounded-full h-16 w-16 border-4 border-teal-200 border-t-teal-600 mb-4"></div>
          <p className="text-gray-700 font-medium">Loading patients...</p>
        </div>
      </div>
    );
  }

  /* ============================= RENDER UI ============================= */
  return (
    <div className="p-6 bg-gradient-to-br from-gray-50 to-gray-100 min-h-screen">
      {toast && <Toast {...toast} onClose={() => setToast(null)} />}
      {alert && <SweetAlert {...alert} />}

      {/* FILTER MODAL POPUP */}
      <FilterModal
        open={filterOpen}
        onClose={() => setFilterOpen(false)}
        onApply={(filters) => {
          setAppliedFilters(filters);
          setCurrentPage(1);
          setFilterOpen(false);
        }}
        initial={appliedFilters}
      />

      <div className="max-w-7xl mx-auto">
        {/* HEADER */}
        <div className="mb-8">
          <div className="flex items-center gap-4 mb-3">
            <div className="w-12 h-12 rounded-2xl bg-gradient-to-br from-teal-500 to-emerald-500 flex items-center justify-center shadow-lg">
              <Users className="w-6 h-6 text-white" />
            </div>
            <div>
              <h1 className="text-4xl font-bold text-gray-900">Patient List</h1>
              <p className="text-gray-500 mt-1">Manage and view all patients</p>
            </div>
          </div>
        </div>

        {/* 📊 STATS CARDS (TỪ /stats) */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
          {[
            {
              label: "Total Patients",
              value: stats.total,
              icon: Users,
              iconColor: "text-cyan-600",
              bgColor: "bg-cyan-50",
            },
            {
              label: "Male Patients",
              value: stats.male,
              icon: UserCheck,
              iconColor: "text-blue-600",
              bgColor: "bg-blue-50",
            },
            {
              label: "Female Patients",
              value: stats.female,
              icon: UserCheck,
              iconColor: "text-pink-600",
              bgColor: "bg-pink-50",
            },
          ].map((stat, i) => {
            const Icon = stat.icon;
            return (
              <div
                key={i}
                className="bg-white rounded-2xl p-5 shadow-sm border border-gray-200 hover:shadow-xl transition-all duration-300"
              >
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-gray-500 text-sm">{stat.label}</p>
                    <p className="text-3xl	font-bold text-gray-900 mt-1">
                      {stat.value}
                    </p>
                  </div>
                  <div
                    className={`w-14 h-14 rounded-2xl ${stat.bgColor} flex items-center justify-center`}
                  >
                    <Icon className={`w-8 h-8 ${stat.iconColor}`} />
                  </div>
                </div>
              </div>
            );
          })}
        </div>

        {/* SEARCH + ADD + FILTER */}
        <div className="bg-white rounded-3xl shadow-xl border border-gray-200 overflow-hidden">
          <div className="p-6 border-b bg-gradient-to-r from-gray-50 to-white">
            <div className="flex flex-col sm:flex-row gap-4 items-center justify-between">
              {/* SEARCH */}
              <div className="flex-1 w-full">
                <div className="relative group">
                  <div className="absolute left-4 top-1/2 -translate-y-1/2">
                    {isSearching ? (
                      <Loader2 className="w-5 h-5 text-teal-500 animate-spin" />
                    ) : (
                      <Search className="w-5 h-5 text-gray-400 group-focus-within:text-teal-500 transition-colors" />
                    )}
                  </div>
                  <input
                    value={searchTerm}
                    onChange={(e) => setSearchTerm(e.target.value)}
                    placeholder="Search by name..."
                    className="w-full pl-12 pr-4 py-3.5 border-2 border-gray-200 rounded-2xl bg-white focus:outline-none focus:ring-2 focus:ring-teal-500/20 focus:border-teal-500 transition-all"
                  />
                </div>
              </div>

              {/* BUTTONS */}
              <div className="flex gap-3">
                <button
                  onClick={() => setFilterOpen(true)}
                  className="px-5 py-3.5 rounded-2xl border-2 border-gray-200 hover:border-gray-300 hover:bg-gray-50 transition-all duration-200 flex items-center gap-2 text-gray-700 font-medium hover:shadow-lg"
                >
                  <Filter className="w-4 h-4" />
                  <span className="hidden sm:inline">Filter</span>
                </button>

                <button
                  onClick={() => navigate("/patients/new")}
                  className="px-6 py-3.5 rounded-2xl bg-gradient-to-r from-teal-500 to-emerald-500 text-white flex items-center gap-2"
                >
                  <Plus className="w-5 h-5" /> Add Patient
                </button>
              </div>
            </div>
          </div>

          {/* TABLE */}
          <div className="overflow-x-auto relative">
            <table className="w-full">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-6 py-4 text-xs font-bold uppercase text-left">
                    ID
                  </th>
                  <th className="px-6 py-4 text-xs font-bold uppercase text-left">
                    Patient
                  </th>
                  <th className="px-6 py-4 text-xs font-bold uppercase text-left">
                    DOB
                  </th>
                  <th className="px-6 py-4 text-xs font-bold uppercase text-left">
                    Gender
                  </th>
                  <th className="px-6 py-4 text-xs font-bold uppercase text-left">
                    Email
                  </th>
                  <th className="px-6 py-4 text-xs font-bold uppercase text-center">
                    Actions
                  </th>
                </tr>
              </thead>

              <tbody className="divide-y divide-gray-100">
                {patients.map((p, i) => (
                  <tr key={p.patientId} className="hover:bg-gray-50">
                    <td className="px-6 py-5 font-mono text-xs text-gray-600">
                      {p.patientId.slice(0, 6).toUpperCase()}
                    </td>

                    <td className="px-6 py-5">
                      <div className="flex items-center gap-4">
                        <Avatar name={p.fullName} gender={p.gender} />
                        <div className="font-semibold text-gray-900">
                          {p.fullName}
                        </div>
                      </div>
                    </td>

                    <td className="px-6 py-5">{p.dob}</td>

                    <td className="px-6 py-5">
                      <span
                        className={`px-3 py-1 rounded-full text-xs font-medium ${
                          p.gender?.toLowerCase() === "male"
                            ? "bg-blue-100 text-blue-700"
                            : "bg-pink-100 text-pink-700"
                        }`}
                      >
                        {p.gender}
                      </span>
                    </td>

                    <td className="px-6 py-5">{p.email}</td>

                    <td className="px-6 py-5 text-center flex justify-center gap-2">
                      <button
                        onClick={() => navigate(`/patients/${p.patientId}`)}
                        className="p-2 rounded-xl hover:bg-teal-50"
                      >
                        <Eye className="w-5 h-5 text-teal-600" />
                      </button>

                      <button
                        onClick={() =>
                          navigate(`/patients/${p.patientId}/edit`)
                        }
                        className="p-2 rounded-xl hover:bg-blue-50"
                      >
                        <Edit3 className="w-5 h-5 text-blue-600" />
                      </button>

                      <button
                        onClick={() => handleDelete(p)}
                        className="p-2 rounded-xl hover:bg-red-50"
                      >
                        <Trash2 className="w-5 h-5 text-red-600" />
                      </button>
                    </td>
                  </tr>
                ))}

                {patients.length === 0 && (
                  <tr>
                    <td colSpan={7} className="px-6 py-20 text-center">
                      <div className="flex flex-col items-center">
                        <UserX className="w-12 h-12 text-gray-400" />
                        <p className="text-gray-600 mt-3">No patients found</p>
                      </div>
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>

          <PaginationControls
            page={currentPage - 1}
            size={pageSize}
            currentPageSize={patients.length}
            totalElements={totalElements}
            totalPages={totalPages}
            onPageChange={(p) => {
              setCurrentPage(p + 1);
            }}
            onSizeChange={(s) => {
              setPageSize(s);
              setCurrentPage(1);
            }}
          />
        </div>
      </div>

      {/* ANIMATIONS */}
      <style>{`
        @keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }
        @keyframes scaleIn { from { opacity: 0; transform: scale(0.9); } to { opacity: 1; transform: scale(1); } }
        @keyframes slideIn { from { opacity: 0; transform: translateX(100px); } to { opacity: 1; transform: translateX(0); } }
      `}</style>
    </div>
  );
}

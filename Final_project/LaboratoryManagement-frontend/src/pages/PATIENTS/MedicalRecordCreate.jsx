/* eslint-disable */
import React, { useState, useRef, useEffect } from "react";
import { useParams, useNavigate } from "react-router-dom";
import axios from "axios";
import Swal from "sweetalert2";
import {
  Calendar,
  ClipboardList,
  FileText,
  ArrowLeft,
  PlusCircle,
  MessageSquare,
  ChevronDown,
} from "lucide-react";

const PATIENT_API_BASE =
  import.meta.env.VITE_API_TESTORDER_PATIENT || "https://be2.flaboratory.cloud";

export default function MedicalRecordCreate() {
  const { patientId } = useParams();
  const navigate = useNavigate();

  const getCurrentLocalDatetime = () => {
    const now = new Date();
    const off = now.getTimezoneOffset();
    const local = new Date(now.getTime() - off * 60000);
    return local.toISOString().slice(0, 16);
  };

  const DEPARTMENT_OPTIONS = [
    "Internal Medicine",
    "Surgery",
    "Cardiology",
    "ENT",
    "Pediatrics",
    "Dermatology",
  ];

  const dropdownRef = useRef(null);
  const [openDeptDrop, setOpenDeptDrop] = useState(false);

  const [form, setForm] = useState({
    visitDate: getCurrentLocalDatetime(),
    diagnosis: "",
    chiefComplaint: "",
    departments: [],
    clinicalNotes: "",
  });

  const [errors, setErrors] = useState({});

  useEffect(() => {
    const handler = (e) => {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target)) {
        setOpenDeptDrop(false);
      }
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, []);

  const toggleDept = (v) => {
    setForm((prev) => ({
      ...prev,
      departments: prev.departments.includes(v)
        ? prev.departments.filter((x) => x !== v)
        : [...prev.departments, v],
    }));
  };

  const validate = () => {
    const e = {};
    if (!form.visitDate) e.visitDate = "Visit date is required";
    if (!form.chiefComplaint.trim())
      e.chiefComplaint = "Chief complaint is required";
    if (form.departments.length === 0)
      e.departments = "Please select at least one department";

    setErrors(e);
    return Object.keys(e).length === 0;
  };

  const handleSubmit = async (e) => {
    e.preventDefault();

    // Validate UI
    if (!validate()) return;

    // HARD CHECK: Department bắt buộc
    if (form.departments.length === 0) {
      Swal.fire({
        icon: "warning",
        title: "Missing Department",
        text: "Please select at least one department.",
      });
      return; // ❗ Stop: Không gửi API
    }

    const token = localStorage.getItem("lm.access");

    const payload = {
      patientId,
      visitDate: form.visitDate,
      diagnosis: form.diagnosis || null,
      chiefComplaint: form.chiefComplaint,
      departments: form.departments,
      clinicalNotes: {
        note: form.clinicalNotes,
      },
    };

    try {
      await axios.post(
        `${PATIENT_API_BASE}/api/v1/patients/${patientId}/medical-records`,
        payload,
        {
          headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
          },
        }
      );

      Swal.fire({
        icon: "success",
        title: "Success",
        text: "Medical record created successfully!",
        timer: 1500,
      });

      navigate(`/patients/${patientId}`);
    } catch (err) {
      Swal.fire({
        icon: "error",
        title: "Error",
        text: err.response?.data?.message || "Failed to create medical record.",
      });
    }
  };

  return (
    <>
      <div className="min-h-screen bg-gradient-to-br from-emerald-50 via-sky-50 to-indigo-50 p-6">
        <button
          onClick={() => navigate(`/patients/${patientId}`)}
          className="inline-flex items-center gap-2 text-gray-600 hover:text-emerald-600 mb-6"
        >
          <ArrowLeft className="w-5 h-5" />
          Back to Patient Details
        </button>

        <div className="bg-white p-8 rounded-3xl shadow-xl">
          <div className="flex items-center gap-3 mb-8">
            <div className="p-3 rounded-2xl bg-gradient-to-br from-emerald-500 to-sky-600">
              <PlusCircle className="w-8 h-8 text-white" />
            </div>
            <div>
              <h1 className="text-3xl font-bold bg-gradient-to-r from-emerald-600 to-sky-600 bg-clip-text text-transparent">
                Create New Medical Record
              </h1>
              <p className="text-sm text-gray-500 mt-1">
                Fill in the medical record details below
              </p>
            </div>
          </div>

          <form onSubmit={handleSubmit} className="space-y-6">
            {/* Visit Date */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Visit Date <span className="text-red-500">*</span>
              </label>
              <div className="relative">
                <Calendar className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                <input
                  type="datetime-local"
                  name="visitDate"
                  value={form.visitDate}
                  onChange={(e) =>
                    setForm((prev) => ({ ...prev, visitDate: e.target.value }))
                  }
                  className="w-full rounded-xl border-2 border-emerald-200 pl-10 pr-4 py-3 focus:border-emerald-500 focus:outline-none transition-colors"
                />
              </div>
              {errors.visitDate && (
                <p className="text-red-500 text-sm mt-1">{errors.visitDate}</p>
              )}
            </div>

            {/* Chief Complaint */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Chief Complaint <span className="text-red-500">*</span>
              </label>

              <div className="relative">
                <MessageSquare className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                <input
                  type="text"
                  placeholder="Enter chief complaint..."
                  value={form.chiefComplaint}
                  onChange={(e) =>
                    setForm((prev) => ({
                      ...prev,
                      chiefComplaint: e.target.value,
                    }))
                  }
                  className="w-full rounded-xl border-2 border-emerald-200 pl-10 pr-4 py-3 focus:border-emerald-500 focus:outline-none transition-colors"
                />
              </div>

              {errors.chiefComplaint && (
                <p className="text-red-500 text-sm mt-1">
                  {errors.chiefComplaint}
                </p>
              )}
            </div>

            {/* Diagnosis */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Diagnosis
              </label>
              <div className="relative">
                <ClipboardList className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                <input
                  type="text"
                  name="diagnosis"
                  value={form.diagnosis}
                  onChange={(e) =>
                    setForm((prev) => ({ ...prev, diagnosis: e.target.value }))
                  }
                  className="w-full rounded-xl border-2 border-emerald-200 pl-10 pr-4 py-3 focus:border-emerald-500 focus:outline-none transition-colors"
                  placeholder="Enter diagnosis"
                />
              </div>
            </div>

            {/* Department DROPDOWN */}
            <div ref={dropdownRef}>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Department <span className="text-red-500">*</span>
              </label>

              <button
                type="button"
                onClick={() => setOpenDeptDrop((o) => !o)}
                className="w-full border-2 border-emerald-200 rounded-xl px-4 py-3 text-left flex items-center gap-2 hover:border-emerald-400 transition-colors"
              >
                <MessageSquare className="w-5 h-5 text-gray-400" />
                <span className="text-gray-700">
                  {form.departments.length === 0
                    ? "Select departments"
                    : `${form.departments.length} selected`}
                </span>
                <ChevronDown className="ml-auto text-gray-500" />
              </button>

              {openDeptDrop && (
                <div className="mt-2 bg-white border-2 border-emerald-200 rounded-2xl shadow-lg p-4 max-h-[300px] overflow-y-auto z-50">
                  <h3 className="font-semibold mb-2">Departments</h3>

                  {DEPARTMENT_OPTIONS.map((opt) => (
                    <label
                      key={opt}
                      className="flex items-center gap-2 py-1 cursor-pointer hover:bg-emerald-50 rounded px-2 transition-colors"
                    >
                      <input
                        type="checkbox"
                        checked={form.departments.includes(opt)}
                        onChange={() => toggleDept(opt)}
                        className="accent-emerald-500"
                      />
                      <span>{opt}</span>
                    </label>
                  ))}
                </div>
              )}

              {errors.departments && (
                <p className="text-red-500 text-sm mt-2">
                  {errors.departments}
                </p>
              )}
            </div>

            {/* TAGS */}
            <div className="flex flex-col gap-2 mt-3">
              {form.chiefComplaint.trim() !== "" && (
                <span className="px-3 py-2 rounded-xl font-medium border-2 border-emerald-200 text-gray-800 bg-emerald-50">
                  <b>Chief Complaint:</b> {form.chiefComplaint}
                </span>
              )}

              {form.departments.length > 0 && (
                <span className="px-3 py-2 rounded-xl font-medium border-2 border-sky-200 text-gray-800 bg-sky-50">
                  <b>Departments:</b> {form.departments.join(", ")}
                </span>
              )}
            </div>

            {/* Clinical Notes */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Clinical Notes
              </label>
              <div className="relative">
                <FileText className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                <textarea
                  name="clinicalNotes"
                  rows="4"
                  value={form.clinicalNotes}
                  onChange={(e) =>
                    setForm((prev) => ({
                      ...prev,
                      clinicalNotes: e.target.value,
                    }))
                  }
                  className="w-full rounded-xl border-2 border-emerald-200 pl-10 pr-4 py-3 resize-none focus:border-emerald-500 focus:outline-none transition-colors"
                  placeholder="Enter clinical notes..."
                />
              </div>
            </div>

            {/* Buttons */}
            <div className="flex justify-end gap-4 pt-6 border-t">
              <button
                type="button"
                onClick={() => navigate(`/patients/${patientId}`)}
                className="px-6 py-3 rounded-xl border-2 border-gray-200 hover:bg-gray-50 transition-all"
              >
                Cancel
              </button>

              <button
                type="submit"
                className="px-8 py-3 rounded-xl text-white font-medium shadow-lg bg-gradient-to-r from-emerald-500 to-sky-600 hover:from-sky-600 hover:to-emerald-500 flex items-center gap-2 transition-all"
              >
                <PlusCircle className="w-5 h-5" />
                Create Record
              </button>
            </div>
          </form>
        </div>
      </div>
    </>
  );
}

/* eslint-disable no-unused-vars */
import React, { useState, useEffect, useRef } from "react";
import { useParams, useNavigate } from "react-router-dom";
import axios from "axios";
import Swal from "sweetalert2";
import {
  ArrowLeft,
  FileText,
  ClipboardList,
  MessageSquare,
  Calendar,
  Hash,
  Save,
  ChevronDown,
} from "lucide-react";

const API_BASE =
  import.meta.env.VITE_API_TESTORDER_PATIENT || "https://be2.flaboratory.cloud";

export default function MedicalRecordEdit() {
  const { patientId, recordId } = useParams();
  const navigate = useNavigate();

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
    recordCode: "",
    visitDate: "",
    diagnosis: "",
    chiefComplaint: "",
    departments: [],
    clinicalNotes: "",
  });

  const [errors, setErrors] = useState({}); // ✅ NEW

  const [loading, setLoading] = useState(true);

  const callApi = async (endpoint, options = {}) => {
    const token = localStorage.getItem("lm.access");
    const url = `${API_BASE}${endpoint}`;
    return axios({
      url,
      ...options,
      headers: {
        Authorization: token ? `Bearer ${token}` : undefined,
        "Content-Type": "application/json",
        ...options.headers,
      },
    });
  };

  useEffect(() => {
    loadRecord();
  }, [patientId, recordId]);

  useEffect(() => {
    const handler = (e) => {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target)) {
        setOpenDeptDrop(false);
      }
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, []);

  const parseDepartments = (r) => {
    if (Array.isArray(r.departments)) return r.departments;
    if (typeof r.department === "string")
      return r.department.split(",").map((x) => x.trim());
    return [];
  };

  const loadRecord = async () => {
    try {
      const res = await callApi(
        `/api/v1/patients/${patientId}/medical-records/${recordId}`
      );
      const r = res.data;

      const parsedDepartments = parseDepartments(r);

      setForm({
        recordCode: r.recordCode || "",
        visitDate: r.visitDate ? r.visitDate.substring(0, 16) : "",
        diagnosis: r.diagnosis || "",
        chiefComplaint: r.chiefComplaint || "",
        departments: parsedDepartments,
        clinicalNotes:
          typeof r.clinicalNotes === "string"
            ? r.clinicalNotes
            : r.clinicalNotes?.note || "",
      });
    } catch (err) {
      Swal.fire("Error", "Failed to load medical record.", "error");
    } finally {
      setLoading(false);
    }
  };

  const toggleDept = (v) => {
    setForm((prev) => ({
      ...prev,
      departments: prev.departments.includes(v)
        ? prev.departments.filter((x) => x !== v)
        : [...prev.departments, v],
    }));
  };

  const safeParseClinicalNotes = (value) => {
    return { note: value };
  };

  // ✅ VALIDATION GIỐNG CREATE
  const validate = () => {
    const e = {};

    if (form.departments.length === 0) {
      e.departments = "Please select at least one department";
    }

    setErrors(e);
    return Object.keys(e).length === 0;
  };

  const handleSubmit = async (e) => {
    e.preventDefault();

    // ⛔ Chặn submit nếu không hợp lệ
    if (!validate()) return;

    try {
      await callApi(
        `/api/v1/patients/${patientId}/medical-records/${recordId}`,
        {
          method: "PUT",
          data: {
            ...form,
            departments: form.departments,
            clinicalNotes: safeParseClinicalNotes(form.clinicalNotes),
          },
        }
      );

      Swal.fire("Success", "Record updated successfully!", "success");
      navigate(`/patients/${patientId}/medical-records/${recordId}`);
    } catch (error) {
      Swal.fire(
        "Error",
        error.response?.data?.message || "Failed to update record.",
        "error"
      );
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-emerald-50 via-sky-50 to-indigo-50">
        <div className="text-center">
          <div className="inline-block w-12 h-12 border-4 border-emerald-200 border-t-emerald-600 rounded-full animate-spin mb-4"></div>
          <p className="text-gray-700 font-medium">Loading medical record...</p>
        </div>
      </div>
    );
  }

  return (
    <>
      <div className="min-h-screen bg-gradient-to-br from-emerald-50 via-sky-50 to-indigo-50 p-6">
        <button
          onClick={() =>
            navigate(`/patients/${patientId}/medical-records/${recordId}`)
          }
          className="inline-flex items-center gap-2 text-gray-600 hover:text-emerald-600 mb-6"
        >
          <ArrowLeft className="w-5 h-5" />
          Back
        </button>

        <div className="bg-white p-8 rounded-3xl shadow-xl">
          <div className="flex items-center gap-3 mb-8">
            <div className="p-3 rounded-2xl bg-gradient-to-br from-emerald-500 to-sky-600">
              <Save className="w-8 h-8 text-white" />
            </div>
            <div>
              <h1 className="text-3xl font-bold bg-gradient-to-r from-emerald-600 to-sky-600 bg-clip-text text-transparent">
                Edit Medical Record
              </h1>
              <p className="text-sm text-gray-500 mt-1">
                Update record details below
              </p>
            </div>
          </div>

          <form onSubmit={handleSubmit} className="space-y-6">
            {/* Record Code */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Record Code
              </label>
              <input
                value={form.recordCode}
                disabled
                className="w-full rounded-xl border-2 border-gray-200 bg-gray-100 px-4 py-3"
              />
            </div>

            {/* Visit Date */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Visit Date
              </label>
              <div className="relative">
                <Calendar className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                <input
                  type="datetime-local"
                  name="visitDate"
                  value={form.visitDate}
                  onChange={(e) =>
                    setForm((p) => ({ ...p, visitDate: e.target.value }))
                  }
                  className="w-full rounded-xl border-2 border-emerald-200 pl-10 pr-4 py-3 focus:border-emerald-500 focus:outline-none transition-colors"
                />
              </div>
            </div>

            {/* Diagnosis */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Diagnosis
              </label>
              <div className="relative">
                <ClipboardList className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                <input
                  name="diagnosis"
                  value={form.diagnosis}
                  onChange={(e) =>
                    setForm((p) => ({ ...p, diagnosis: e.target.value }))
                  }
                  className="w-full rounded-xl border-2 border-emerald-200 pl-10 pr-4 py-3 focus:border-emerald-500 focus:outline-none transition-colors"
                  placeholder="Enter diagnosis..."
                />
              </div>
            </div>

            {/* Chief Complaint */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Chief Complaint
              </label>
              <div className="relative">
                <MessageSquare className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                <input
                  name="chiefComplaint"
                  value={form.chiefComplaint}
                  onChange={(e) =>
                    setForm((p) => ({
                      ...p,
                      chiefComplaint: e.target.value,
                    }))
                  }
                  className="w-full rounded-xl border-2 border-emerald-200 pl-10 pr-4 py-3 focus:border-emerald-500 focus:outline-none transition-colors"
                  placeholder="Enter chief complaint..."
                />
              </div>
            </div>

            {/* Department */}
            <div ref={dropdownRef}>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Departments <span className="text-red-500">*</span>
              </label>

              <button
                type="button"
                onClick={() => setOpenDeptDrop((o) => !o)}
                className={`w-full border-2 rounded-xl px-4 py-3 text-left flex items-center gap-2 hover:border-emerald-400 transition-colors ${
                  errors.departments ? "border-red-400" : "border-emerald-200"
                }`}
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
                    setForm((p) => ({
                      ...p,
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
                onClick={() =>
                  navigate(`/patients/${patientId}/medical-records/${recordId}`)
                }
                className="px-6 py-3 rounded-xl border-2 border-gray-200 hover:bg-gray-50 transition-all"
              >
                Cancel
              </button>

              <button
                type="submit"
                className="px-8 py-3 rounded-xl text-white font-medium shadow-lg bg-gradient-to-r from-emerald-500 to-sky-600 hover:from-sky-600 hover:to-emerald-500 flex items-center gap-2 transition-all"
              >
                <Save className="w-5 h-5" />
                Save Changes
              </button>
            </div>
          </form>
        </div>
      </div>
    </>
  );
}

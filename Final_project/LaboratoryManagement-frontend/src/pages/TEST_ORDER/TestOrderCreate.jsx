import React, { useState, useEffect } from "react";
import { useLocation, useNavigate } from "react-router-dom";
import Swal from "sweetalert2";
import axios from "axios";
import { createTestOrder } from "../../services/testorderApi";

import {
  ClipboardList,
  User,
  Stethoscope,
  ListChecks,
  ArrowLeft,
} from "lucide-react";

const API_BASE =
  import.meta.env.VITE_API_TESTORDER || "https://be2.flaboratory.cloud";

export default function TestOrderCreate() {
  const navigate = useNavigate();
  const { state } = useLocation();

  const {
    medicalRecordId,
    patientId,
    patientName,
    age,
    gender,
    phoneNumber,
    email,
    address,
    dateOfBirth,
  } = state || {};

  const [form, setForm] = useState({
    priority: "NORMAL",
  });

  const [submitting, setSubmitting] = useState(false);

  const [testTypes, setTestTypes] = useState([]);
  const [loadingTypes, setLoadingTypes] = useState(false);
  const [selectedTestTypeIds, setSelectedTestTypeIds] = useState([]);

  useEffect(() => {
    loadTestTypes();
  }, []);

  const loadTestTypes = async () => {
    try {
      setLoadingTypes(true);
      const token = localStorage.getItem("lm.access");

      const res = await axios.get(`${API_BASE}/api/v1/test-types`, {
        headers: {
          Authorization: token ? `Bearer ${token}` : undefined,
        },
      });

      const data = Array.isArray(res.data)
        ? res.data
        : res.data?.content || res.data?.items || [];

      setTestTypes(data);
    } catch (error) {
      console.error("Error loading test types:", error);
      Swal.fire("Error", "Failed to load test types.", "error");
    } finally {
      setLoadingTypes(false);
    }
  };

  const handleChange = (e) => {
    const { name, value } = e.target;
    setForm((p) => ({ ...p, [name]: value }));
  };

  const toggleTestType = (id) => {
    setSelectedTestTypeIds((prev) =>
      prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]
    );
  };

  const handleSubmit = async (e) => {
    e.preventDefault();

    if (!medicalRecordId) {
      Swal.fire("Error", "Missing medical record id.", "error");
      return;
    }

    if (selectedTestTypeIds.length === 0) {
      Swal.fire(
        "Missing Tests",
        "Please select at least one test type.",
        "warning"
      );
      return;
    }

    const orderNumber = `TO-${Date.now()}`;

    const patientSnapshot = {
      patientId,
      patientName,
      age,
      gender,
      phoneNumber,
      email,
      address,
      dateOfBirth,
    };

    const payload = {
      orderNumber,
      medicalRecordId,
      priority: form.priority,
      testTypeIds: selectedTestTypeIds,
      patientSnapshot,
    };

    try {
      setSubmitting(true);
      await createTestOrder(payload);

      Swal.fire({
        icon: "success",
        title: "Success",
        text: "Test order created successfully!",
        timer: 1500,
        showConfirmButton: false,
      });

      navigate(`/patients/${patientId}/medical-records/${medicalRecordId}`, {
        replace: true,
      });
    } catch (err) {
      let msg =
        err.response?.data?.message ||
        err.response?.data?.error ||
        "Failed to create test order";

      Swal.fire("Error", msg, "error");
    } finally {
      setSubmitting(false);
    }
  };

  const handleCancel = () => navigate(-1);

  const ReadOnlyField = ({ label, value, isTextArea = false }) => (
    <div>
      <label className="block text-sm font-medium text-gray-700 mb-2">
        {label}
      </label>
      {isTextArea ? (
        <textarea
          value={value || ""}
          readOnly
          rows={2}
          className="w-full rounded-xl border-2 border-gray-200 bg-gray-50
        px-4 py-3 text-gray-700 resize-none focus:outline-none cursor-default"
        />
      ) : (
        <input
          type="text"
          value={value || ""}
          readOnly
          className="w-full rounded-xl border-2 border-gray-200 bg-gray-50
        px-4 py-3 text-gray-700 focus:outline-none cursor-default"
        />
      )}
    </div>
  );

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
        <div className="max-w-7xl mx-auto">
          <button
            onClick={handleCancel}
            className="inline-flex items-center gap-2 text-gray-600 hover:text-emerald-600 font-medium mb-6 transition-colors"
          >
            <ArrowLeft className="w-5 h-5" />
            Back to Medical Record
          </button>

          <div className="bg-white rounded-3xl shadow-xl p-8 fade-in">
            <div className="flex items-center gap-3 mb-8">
              <div className="p-3 rounded-2xl bg-gradient-to-br from-emerald-500 to-sky-600">
                <ClipboardList className="w-8 h-8 text-white" />
              </div>
              <div>
                <h1 className="text-3xl font-bold bg-gradient-to-r from-emerald-600 to-sky-600 bg-clip-text text-transparent">
                  Create Test Order
                </h1>
                <p className="text-sm text-gray-500 mt-1">
                  Medical Record ID: {medicalRecordId || "N/A"}
                </p>
              </div>
            </div>

            <form onSubmit={handleSubmit} className="space-y-8">
              <section className="space-y-4">
                <h3 className="text-lg font-semibold text-gray-700 flex items-center gap-2 pt-6 border-t -mt-6">
                  <User className="w-5 h-5 text-emerald-500" />
                  Patient Information Snapshot
                </h3>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <ReadOnlyField label="Full Name" value={patientName} />

                  <ReadOnlyField label="Age" value={age ?? ""} />

                  <ReadOnlyField label="Gender" value={gender} />

                  <ReadOnlyField label="Phone Number" value={phoneNumber} />

                  <ReadOnlyField label="Email" value={email} />

                  <ReadOnlyField
                    label="Date of Birth"
                    value={
                      dateOfBirth
                        ? new Date(dateOfBirth).toLocaleDateString()
                        : ""
                    }
                  />

                  <div className="md:col-span-2">
                    <ReadOnlyField
                      label="Address"
                      value={address}
                      isTextArea={true}
                    />
                  </div>
                </div>
              </section>

              <section className="space-y-4 pt-6 border-t">
                <h3 className="text-lg font-semibold text-gray-700 flex items-center gap-2">
                  <Stethoscope className="w-5 h-5 text-sky-500" />
                  Order Details
                </h3>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div>
                    <label className="block text-sm font-medium text-gray-700 mb-2">
                      Priority
                    </label>

                    <select
                      name="priority"
                      value={form.priority}
                      onChange={handleChange}
                      className="w-full rounded-xl border-2 border-gray-200 px-4 py-3 focus:border-emerald-500 focus:outline-none transition"
                    >
                      <option value="URGENT">URGENT</option>
                      <option value="HIGH">HIGH</option>
                      <option value="LOW">LOW</option>
                      <option value="NORMAL">NORMAL</option>
                    </select>
                  </div>
                </div>
              </section>

              <section className="space-y-4 pt-6 border-t">
                <h3 className="text-lg font-semibold text-gray-700 flex items-center gap-2">
                  <ListChecks className="w-5 h-5 text-indigo-500" />
                  Select Test Types
                </h3>

                {loadingTypes ? (
                  <p className="text-gray-500">Loading test types...</p>
                ) : testTypes.length === 0 ? (
                  <p className="text-gray-500">No test types available.</p>
                ) : (
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-3 max-h-64 overflow-y-auto border border-gray-200 rounded-xl p-4">
                    {testTypes.map((tt) => (
                      <label
                        key={tt.id}
                        className="flex items-center gap-3 cursor-pointer p-1 hover:bg-emerald-50 rounded-lg transition"
                      >
                        <input
                          type="checkbox"
                          checked={selectedTestTypeIds.includes(tt.id)}
                          onChange={() => toggleTestType(tt.id)}
                          className="w-5 h-5 rounded border-gray-300 text-emerald-600 focus:ring-emerald-500"
                        />
                        <span className="text-gray-700">
                          <strong>{tt.code || tt.testTypeCode}</strong> —{" "}
                          {tt.name || tt.testTypeName}
                        </span>
                      </label>
                    ))}
                  </div>
                )}
              </section>

              <div className="flex justify-end gap-4 pt-6 border-t">
                <button
                  type="button"
                  onClick={handleCancel}
                  className="px-6 py-3 rounded-xl border-2 border-gray-200 hover:border-gray-300 hover:bg-gray-50 transition-all font-medium"
                >
                  Cancel
                </button>

                <button
                  type="submit"
                  disabled={submitting}
                  className="px-8 py-3 rounded-xl text-white font-medium shadow-lg bg-gradient-to-r from-emerald-500 to-sky-600 hover:from-sky-600 hover:to-emerald-500 transition disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
                >
                  <ClipboardList className="w-5 h-5" />
                  {submitting ? "Creating..." : "Create Test Order"}
                </button>
              </div>
            </form>
          </div>
        </div>
      </div>
    </>
  );
}

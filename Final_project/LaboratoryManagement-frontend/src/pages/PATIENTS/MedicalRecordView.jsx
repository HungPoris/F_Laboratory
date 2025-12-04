import React, { useState, useEffect } from "react";
import { useParams, Link, useNavigate } from "react-router-dom";
import axios from "axios";
import Swal from "sweetalert2";

const API_BASE =
  import.meta.env.VITE_API_TESTORDER_PATIENT || "https://be2.flaboratory.cloud";

export default function MedicalRecordView() {
  const { patientId, recordId } = useParams();
  const navigate = useNavigate();
  const [record, setRecord] = useState(null);
  const [loading, setLoading] = useState(true);

  // helper gọi API có token
  const callApi = async (endpoint, options = {}) => {
    const token = localStorage.getItem("lm.access");
    const url = `${API_BASE}${endpoint}`;
    return axios({
      url,
      ...options,
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
        ...options.headers,
      },
      withCredentials: true,
    });
  };

  useEffect(() => {
    loadRecord();
  }, [patientId, recordId]);

  const loadRecord = async () => {
    try {
      setLoading(true);
      const res = await callApi(
        `/api/v1/patient/${patientId}/medical-records/${recordId}`
      );
      setRecord(res.data);
    } catch (error) {
      console.error("Error loading record:", error);
      Swal.fire({
        icon: "error",
        title: "Error",
        text: error.response?.data?.message || "Failed to load medical record",
      });
    } finally {
      setLoading(false);
    }
  };

  const handleBack = () => {
    navigate(`/patients/${patientId}`);
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="text-center">
          <div className="inline-block animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600 mb-4"></div>
          <p className="text-gray-600">Loading record details...</p>
        </div>
      </div>
    );
  }

  if (!record) {
    return (
      <div className="container mx-auto px-4 py-6 text-center">
        <h1 className="text-2xl font-bold mb-2">Record Not Found</h1>
        <p className="text-gray-600 mb-4">
          The medical record you’re looking for could not be found.
        </p>
        <button
          onClick={handleBack}
          className="text-blue-600 hover:text-blue-800 underline"
        >
          ← Back to Patient Details
        </button>
      </div>
    );
  }

  return (
    <div className="container mx-auto px-4 py-6">
      <div className="flex justify-between items-center mb-6">
        <h1 className="text-3xl font-bold text-gray-800">
          Medical Record Details
        </h1>
        <button
          onClick={handleBack}
          className="bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700"
        >
          ← Back to Patient
        </button>
      </div>

      <div className="bg-white shadow-md rounded-lg p-6 space-y-4">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Record Code
          </label>
          <p className="text-gray-900">{record.recordCode}</p>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Visit Date
          </label>
          <p className="text-gray-900">
            {record.visitDate
              ? new Date(record.visitDate).toLocaleString()
              : "N/A"}
          </p>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Chief Complaint
          </label>
          <p className="text-gray-900">{record.chiefComplaint || "N/A"}</p>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Diagnosis
          </label>
          <p className="text-gray-900">{record.diagnosis || "N/A"}</p>
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Clinical Notes
          </label>
          <p className="text-gray-900 whitespace-pre-wrap">
            {record.clinicalNotes || "N/A"}
          </p>
        </div>

        <div className="pt-4">
          <button
            onClick={() =>
              navigate(
                `/patients/${patientId}/medical-records/${recordId}/edit`
              )
            }
            className="bg-green-600 text-white px-4 py-2 rounded-lg hover:bg-green-700 mr-3"
          >
            Edit Record
          </button>
          <button
            onClick={() =>
              Swal.fire({
                icon: "info",
                title: "Feature Coming Soon",
                text: "Edit and test history will be added later.",
              })
            }
            className="bg-gray-300 text-gray-800 px-4 py-2 rounded-lg hover:bg-gray-400"
          >
            View Test Orders
          </button>
        </div>
      </div>
    </div>
  );
}

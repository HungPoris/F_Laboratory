/* eslint-disable */
import React, { useState, useEffect } from "react";
import { useParams, useNavigate, Link } from "react-router-dom";
import axios from "axios";
import Swal from "sweetalert2";

import PaginationControls from "../../components/PaginationControls";

const PATIENT_API_BASE =
  import.meta.env.VITE_API_TESTORDER_PATIENT || "https://be2.flaboratory.cloud";

export default function PatientDetail() {
  const { patientId } = useParams();
  const navigate = useNavigate();
  const [patient, setPatient] = useState(null);
  const [loading, setLoading] = useState(true);

  const [medicalRecords, setMedicalRecords] = useState([]);
  const [allMedicalRecords, setAllMedicalRecords] = useState([]);
  const [loadingRecords, setLoadingRecords] = useState(false);

  // 🔹 Phân trang Medical Records (giống PatientList)
  const [page, setPage] = useState(0); // 0-based
  const [pageSize, setPageSize] = useState(10);
  const [totalPages, setTotalPages] = useState(0);
  const [totalElements, setTotalElements] = useState(0);

  const callPatientApi = async (endpoint, options = {}) => {
    const token = localStorage.getItem("lm.access");
    const url = `${PATIENT_API_BASE}${endpoint}`;
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
    loadPatient();
    loadMedicalRecords();
  }, [patientId]);

  const loadPatient = async () => {
    try {
      setLoading(true);
      const response = await callPatientApi(`/api/v1/patients/${patientId}`);
      setPatient(response.data);
    } catch {
      Swal.fire({
        icon: "error",
        title: "Error",
        text: "Failed to load patient details",
      });
    } finally {
      setLoading(false);
    }
  };

  // 🔹 Hàm áp dụng phân trang cho Medical Records (client-side)
  const applyMedicalRecordPagination = (
    list,
    pageIndex = page,
    size = pageSize
  ) => {
    const total = list.length;
    const totalPagesCalc = total === 0 ? 0 : Math.ceil(total / size);
    const safePage =
      totalPagesCalc === 0 ? 0 : Math.min(pageIndex, totalPagesCalc - 1);

    const start = safePage * size;
    const paged = list.slice(start, start + size);

    setMedicalRecords(paged);
    setTotalElements(total);
    setTotalPages(totalPagesCalc);
    setPage(safePage);
  };

  const loadMedicalRecords = async () => {
    try {
      setLoadingRecords(true);
      const response = await callPatientApi(
        `/api/v1/patients/${patientId}/medical-records`
      );
      const list = response.data || [];

      // Lưu toàn bộ records & áp dụng phân trang trang đầu
      setAllMedicalRecords(list);
      applyMedicalRecordPagination(list, 0, pageSize);
    } catch (err) {
      console.error("Error loading medical records:", err);
      setAllMedicalRecords([]);
      applyMedicalRecordPagination([], 0, pageSize);
    } finally {
      setLoadingRecords(false);
    }
  };

  // ⭐⭐⭐ DELETE MEDICAL RECORD
  const handleDeleteRecord = async (recordId) => {
    const result = await Swal.fire({
      title: "Delete medical record?",
      text: "This action cannot be undone!",
      icon: "warning",
      showCancelButton: true,
      confirmButtonColor: "#d33",
      cancelButtonColor: "#3085d6",
      confirmButtonText: "Yes, delete it",
    });

    if (result.isConfirmed) {
      try {
        await callPatientApi(
          `/api/v1/patients/${patientId}/medical-records/${recordId}`,
          { method: "DELETE" }
        );

        Swal.fire({
          icon: "success",
          title: "Deleted!",
          text: "Medical record has been deleted.",
          timer: 1500,
        });

        // Reload danh sách rồi phân trang lại
        await loadMedicalRecords();
      } catch (err) {
        Swal.fire({
          icon: "error",
          title: "Error",
          text: err.response?.data?.message || "Failed to delete record",
        });
      }
    }
  };

  const handleDelete = async () => {
    const result = await Swal.fire({
      title: "Are you sure?",
      text: "This action cannot be undone!",
      icon: "warning",
      showCancelButton: true,
      confirmButtonColor: "#d33",
      cancelButtonColor: "#3085d6",
      confirmButtonText: "Yes, delete it!",
    });

    if (result.isConfirmed) {
      try {
        await callPatientApi(`/api/v1/patients/${patientId}`, {
          method: "DELETE",
        });
        Swal.fire({
          icon: "success",
          title: "Deleted!",
          text: "Patient has been deleted.",
          timer: 1500,
        });
        navigate("/patients");
      } catch (err) {
        Swal.fire({
          icon: "error",
          title: "Error",
          text: err.response?.data?.message || "Failed to delete patient",
        });
      }
    }
  };

  // 🔹 Khi bấm đổi trang (từ PaginationControls)
  const handleMedicalRecordPageChange = (newPage) => {
    applyMedicalRecordPagination(allMedicalRecords, newPage, pageSize);
  };

  // 🔹 Khi đổi page size (giống PatientList - size dropdown)
  const handleMedicalRecordSizeChange = (newSize) => {
    const size = Number(newSize) || 10;
    setPageSize(size);
    applyMedicalRecordPagination(allMedicalRecords, 0, size);
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-gradient-to-br from-cyan-50 via-blue-50 to-teal-50">
        <div className="text-center">
          <div className="inline-block animate-spin rounded-full h-16 w-16 border-4 border-cyan-200 border-t-cyan-600 mb-4"></div>
          <p className="text-gray-700 font-medium">
            Loading patient details...
          </p>
        </div>
      </div>
    );
  }

  if (!patient) {
    return (
      <div className="container mx-auto px-4 py-6 text-center">
        <h1 className="text-2xl font-bold mt-4 mb-2 text-gray-800">
          Patient Not Found
        </h1>
        <Link
          to="/patients"
          className="inline-flex items-center text-cyan-600 hover:text-teal-600 font-medium"
        >
          ← Back to Patient List
        </Link>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-cyan-50 via-blue-50 to-teal-50">
      <div className="container mx-auto px-6 py-8">
        {/* Back link */}
        <Link
          to="/patients"
          className="inline-flex items-center text-cyan-600 hover:text-teal-600 font-medium mb-4"
        >
          <svg
            className="w-5 h-5 mr-2"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M10 19l-7-7m0 0l7-7m-7 7h18"
            />
          </svg>
          Back to Patient List
        </Link>

        {/* Header */}
        <div className="flex flex-col md:flex-row md:items-center md:justify-between bg-white rounded-lg shadow-md p-6 border-l-4 border-cyan-500 mb-8">
          <h1 className="text-3xl font-bold text-gray-800">Patient Details</h1>
          <div className="flex gap-3 mt-4 md:mt-0">
            <Link
              to={`/patients/${patientId}/edit`}
              className="inline-flex items-center gap-2 px-5 py-2 bg-teal-50 text-teal-600 rounded-md hover:bg-teal-100 transition-colors duration-150 font-medium"
            >
              <svg
                className="w-5 h-5"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"
                />
              </svg>
              Edit
            </Link>

            <button
              onClick={handleDelete}
              className="inline-flex items-center gap-2 px-5 py-2 bg-red-50 text-red-600 rounded-md hover:bg-red-100 transition-colors duration-150 font-medium"
            >
              <svg
                className="w-5 h-5"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                />
              </svg>
              Delete
            </button>
          </div>
        </div>

        {/* Personal Information */}
        <div className="bg-white rounded-lg shadow-md p-6 border-l-4 border-cyan-500 mb-8">
          <h2 className="text-xl font-semibold text-gray-800 mb-4 border-b pb-2">
            Personal Information
          </h2>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {[
              [
                "Patient ID",
                (patient.patientId || patient.id).slice(0, 6).toUpperCase(),
              ],
              ["Full Name", patient.fullName || patient.name],
              ["Date of Birth", patient.dob || patient.dateOfBirth],
              ["Gender", patient.gender],
              ["Phone Number", patient.contactNumber || patient.phoneNumber],
              ["Email", patient.email || "N/A"],
              ["Address", patient.address || "N/A"],
            ].map(([label, value]) => (
              <div key={label}>
                <label className="block text-sm font-medium text-gray-500 mb-1">
                  {label}
                </label>
                <p className="text-gray-900 font-medium">{value}</p>
              </div>
            ))}
          </div>
        </div>

        {/* Medical Records */}
        <div className="bg-white rounded-lg shadow-md p-6 border-l-4 border-cyan-500">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-xl font-semibold text-gray-800">
              Medical Records
            </h2>

            <Link
              to={`/patients/${patientId}/medical-records/new`}
              className="inline-flex items-center gap-2 bg-gradient-to-r from-cyan-500 to-teal-500 text-white px-5 py-2 rounded-md hover:from-cyan-600 hover:to-teal-600 shadow-md hover:shadow-lg transition-all duration-200 font-medium"
            >
              <svg
                className="w-5 h-5"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M12 4v16m8-8H4"
                />
              </svg>
              Add Medical Record
            </Link>
          </div>

          {loadingRecords ? (
            <div className="text-center py-8">
              <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-cyan-600"></div>
              <p className="mt-2 text-gray-600">Loading medical records...</p>
            </div>
          ) : medicalRecords.length > 0 ? (
            <>
              <div className="overflow-x-auto">
                <table className="min-w-full divide-y divide-gray-200">
                  <thead className="bg-gray-50">
                    <tr>
                      {["DATE", "DIAGNOSIS", "DEPARTMENTS", "ACTIONS"].map(
                        (h) => (
                          <th
                            key={h}
                            className="px-6 py-4 text-left text-xs font-semibold text-gray-600 uppercase tracking-wider"
                          >
                            {h}
                          </th>
                        )
                      )}
                    </tr>
                  </thead>

                  <tbody className="bg-white divide-y divide-gray-100">
                    {medicalRecords.map((record) => {
                      const departments = Array.isArray(record.departments)
                        ? record.departments.join(", ")
                        : record.department || "N/A";

                      return (
                        <tr
                          key={record.medicalRecordId}
                          className="hover:bg-cyan-50 transition-colors duration-150"
                        >
                          <td className="px-6 py-4 text-sm text-gray-700">
                            {record.visitDate
                              ? new Date(record.visitDate).toLocaleDateString()
                              : "N/A"}
                          </td>

                          <td className="px-6 py-4 text-sm text-gray-700">
                            {record.diagnosis || "N/A"}
                          </td>

                          <td className="px-6 py-4 text-sm text-gray-700">
                            {departments}
                          </td>

                          <td className="px-6 py-4 text-sm font-medium">
                            <div className="flex flex-col gap-1">
                              <div className="flex items-center gap-2">
                                <Link
                                  to={`/patients/${patientId}/medical-records/${record.medicalRecordId}`}
                                  className="inline-flex items-center gap-1 px-3 py-1.5 bg-cyan-50 text-cyan-600 rounded-md hover:bg-cyan-100 transition-colors duration-150 font-medium"
                                >
                                  <svg
                                    className="w-4 h-4"
                                    fill="none"
                                    stroke="currentColor"
                                    viewBox="0 0 24 24"
                                  >
                                    <path
                                      strokeLinecap="round"
                                      strokeLinejoin="round"
                                      strokeWidth={2}
                                      d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
                                    />
                                    <path
                                      strokeLinecap="round"
                                      strokeLinejoin="round"
                                      strokeWidth={2}
                                      d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"
                                    />
                                  </svg>
                                  View
                                </Link>

                                <Link
                                  to={`/patients/${patientId}/medical-records/${record.medicalRecordId}/edit`}
                                  className="inline-flex items-center gap-1 px-3 py-1.5 bg-teal-50 text-teal-600 rounded-md hover:bg-teal-100 transition-colors duration-150 font-medium"
                                >
                                  <svg
                                    className="w-4 h-4"
                                    fill="none"
                                    stroke="currentColor"
                                    viewBox="0 0 24 24"
                                  >
                                    <path
                                      strokeLinecap="round"
                                      strokeLinejoin="round"
                                      strokeWidth={2}
                                      d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"
                                    />
                                  </svg>
                                  Edit
                                </Link>

                                <button
                                  onClick={() =>
                                    handleDeleteRecord(record.medicalRecordId)
                                  }
                                  className="inline-flex items-center gap-1 px-3 py-1.5 bg-red-50 text-red-600 rounded-md hover:bg-red-100 transition-colors duration-150 font-medium"
                                >
                                  <svg
                                    className="w-4 h-4"
                                    fill="none"
                                    stroke="currentColor"
                                    viewBox="0 0 24 24"
                                  >
                                    <path
                                      strokeLinecap="round"
                                      strokeLinejoin="round"
                                      strokeWidth={2}
                                      d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                                    />
                                  </svg>
                                  Delete
                                </button>
                              </div>
                            </div>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>

              {/* 🔹 Phân trang Medical Records – dùng PaginationControls giống PatientList */}
              <PaginationControls
                page={page}
                size={pageSize}
                currentPageSize={medicalRecords.length}
                totalElements={totalElements}
                totalPages={totalPages}
                onPageChange={(p) => handleMedicalRecordPageChange(p)}
                onSizeChange={(s) => handleMedicalRecordSizeChange(s)}
              />
            </>
          ) : (
            <div className="text-center py-12 text-gray-500 font-medium">
              No medical records
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

/* eslint-disable no-unused-vars */
import React, { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { getSystemMedicalRecords } from "../../services/medicalRecordApi";
import { useDebounce } from "../../hooks/useDebounce";
import {
  FileText,
  Search,
  Eye,
  X,
  CheckCircle2,
  AlertCircle,
  Info,
  Loader2,
  SearchCode,
} from "lucide-react";

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

const AllMedicalRecords = () => {
  const navigate = useNavigate();

  const [records, setRecords] = useState([]);
  const [loading, setLoading] = useState(false);
  const [isSearching, setIsSearching] = useState(false);
  const [error, setError] = useState(null);

  const [searchTerm, setSearchTerm] = useState("");
  const debouncedSearchTerm = useDebounce(searchTerm, 500);
  const [hasSearched, setHasSearched] = useState(false);

  const [currentPage, setCurrentPage] = useState(1);
  const [pageSize] = useState(10);
  const [totalPages, setTotalPages] = useState(0);
  const [totalElements, setTotalElements] = useState(0);

  const [toast, setToast] = useState(null);

  const showToast = (message, type = "success") => {
    setToast({ message, type });
  };

  const isValidForSearch = (value) => {
    return /^[\p{L}\p{M}\d\s]+$/u.test(value.trim());
  };

  const handleSearchChange = (e) => {
    const v = e.target.value;
    setSearchTerm(v);
    setCurrentPage(1);
  };

  useEffect(() => {
    const searchLive = async () => {
      if (!debouncedSearchTerm.trim()) {
        setRecords([]);
        setTotalElements(0);
        setTotalPages(0);
        setHasSearched(false);
        return;
      }

      if (!isValidForSearch(debouncedSearchTerm)) {
        showToast(
          "Search only accepts letters and numbers (no special characters)",
          "error"
        );
        return;
      }

      try {
        setLoading(true);
        setIsSearching(true);

        const params = {
          page: currentPage - 1,
          size: pageSize,
          search: debouncedSearchTerm,
        };

        const data = await getSystemMedicalRecords(params);

        if (data && Array.isArray(data.items)) {
          setRecords(data.items);
          setTotalElements(data.totalElements);
          setTotalPages(data.totalPages);
          setHasSearched(true);
        } else {
          setRecords([]);
          setTotalElements(0);
        }
      } catch (err) {
        showToast("Failed to load records", "error");
      } finally {
        setLoading(false);
        setIsSearching(false);
      }
    };

    searchLive();
  }, [debouncedSearchTerm, currentPage]);

  const currentRecords = records;
  const startIndex = (currentPage - 1) * pageSize;

  return (
    <div className="p-6 bg-gradient-to-br from-gray-50 to-gray-100 min-h-screen">
      {toast && <Toast {...toast} onClose={() => setToast(null)} />}

      <div className="max-w-7xl mx-auto">
        <div className="mb-8">
          <div className="flex items-center gap-4 mb-3">
            <div className="w-12 h-12 rounded-2xl bg-gradient-to-br from-teal-500 to-emerald-500 flex items-center justify-center shadow-lg shadow-teal-500/30">
              <FileText className="w-6 h-6 text-white" />
            </div>
            <div>
              <h1 className="text-4xl font-bold text-gray-900">
                Medical Records
              </h1>
              <p className="text-gray-500 mt-1">Search medical records</p>
            </div>
          </div>
        </div>

        <div className="bg-white rounded-3xl shadow-xl border border-gray-200 overflow-hidden">
          <div className="p-6 border-b bg-gradient-to-r from-gray-50 to-white">
            <div className="flex flex-col sm:flex-row gap-4 items-start sm:items-center justify-between">
              <div className="flex-1 w-full sm:w-auto">
                <div className="relative group">
                  <div className="absolute left-4 top-1/2 -translate-y-1/2">
                    {isSearching ? (
                      <Loader2 className="w-5 h-5 text-teal-500 animate-spin" />
                    ) : (
                      <Search className="w-5 h-5 text-gray-400" />
                    )}
                  </div>

                  <input
                    value={searchTerm}
                    onChange={handleSearchChange}
                    placeholder="Search by Patient Name or Record Code..."
                    className="w-full pl-12 pr-4 py-3.5 border-2 border-gray-200 rounded-2xl focus:ring-2 focus:ring-teal-500/20 shadow-sm"
                  />
                </div>
              </div>
            </div>
          </div>

          <div className="overflow-x-auto relative min-h-[400px]">
            {isSearching && (
              <div className="absolute inset-0 bg-white/60 z-10 flex justify-center pt-32"></div>
            )}

            <table className="w-full">
              <thead>
                <tr className="bg-gray-50">
                  <th className="px-6 py-4 text-xs font-bold text-gray-600 uppercase">
                    No.
                  </th>
                  <th className="px-6 py-4 text-xs font-bold text-gray-600 uppercase">
                    Record Code
                  </th>
                  <th className="px-6 py-4 text-xs font-bold text-gray-600 uppercase">
                    Patient
                  </th>
                  <th className="px-6 py-4 text-xs font-bold text-gray-600 uppercase">
                    Diagnosis
                  </th>
                  <th className="px-6 py-4 text-xs font-bold text-gray-600 uppercase">
                    Visit Date
                  </th>
                  <th className="px-6 py-4 text-xs font-bold text-gray-600 uppercase text-center">
                    Actions
                  </th>
                </tr>
              </thead>

              <tbody className="divide-y divide-gray-100">
                {!hasSearched && (
                  <tr>
                    <td colSpan={6} className="px-6 py-32 text-center">
                      <div className="flex flex-col items-center gap-4">
                        <div className="w-24 h-24 bg-teal-50 rounded-full flex items-center justify-center">
                          <SearchCode className="w-12 h-12 text-teal-500" />
                        </div>
                        <h3 className="text-xl font-semibold text-gray-700">
                          Ready to search
                        </h3>
                        <p className="text-gray-500">
                          Enter a record code or patient name to begin.
                        </p>
                      </div>
                    </td>
                  </tr>
                )}

                {hasSearched &&
                  currentRecords.map((r, index) => (
                    <tr
                      key={r.medicalRecordId}
                      className="hover:bg-gray-50 transition-all"
                    >
                      <td className="px-6 py-5">{startIndex + index + 1}</td>
                      <td className="px-6 py-5">
                        <span className="text-sm font-mono bg-teal-50 text-teal-600 px-3 py-1.5 rounded-lg">
                          {r.recordCode}
                        </span>
                      </td>
                      <td className="px-6 py-5 font-semibold text-gray-900">
                        {r.patientName}
                      </td>
                      <td className="px-6 py-5 text-gray-700">
                        {r.diagnosis || (
                          <span className="italic text-gray-400">
                            No diagnosis
                          </span>
                        )}
                      </td>
                      <td className="px-6 py-5">
                        {r.visitDate ? (
                          new Date(r.visitDate).toLocaleDateString("en-US", {
                            year: "numeric",
                            month: "short",
                            day: "numeric",
                          })
                        ) : (
                          <span className="text-gray-400">N/A</span>
                        )}
                      </td>
                      <td className="px-6 py-5 text-center">
                        <button
                          onClick={() =>
                            navigate(
                              `/patients/${r.patientId}/medical-records/${r.medicalRecordId}`
                            )
                          }
                          className="p-2.5 rounded-xl hover:bg-teal-50 transition-all shadow-sm"
                        >
                          <Eye className="w-4 h-4 text-teal-600" />
                        </button>
                      </td>
                    </tr>
                  ))}

                {hasSearched && !isSearching && currentRecords.length === 0 && (
                  <tr>
                    <td colSpan={6} className="px-6 py-20 text-center">
                      <div className="flex flex-col items-center gap-4">
                        <div className="w-20 h-20 bg-gray-100 rounded-full flex items-center justify-center">
                          <FileText className="w-10 h-10 text-gray-400" />
                        </div>
                        <p className="text-lg font-semibold text-gray-700">
                          No records found
                        </p>
                      </div>
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>

          {hasSearched && totalElements > 0 && (
            <div className="p-6 bg-gray-50 border-t flex items-center justify-between">
              <p className="text-sm text-gray-600">
                Showing <b>{startIndex + 1}</b>–
                <b>{Math.min(startIndex + pageSize, totalElements)}</b> of{" "}
                <b>{totalElements}</b>
              </p>

              <div className="flex items-center gap-2">
                <button
                  disabled={currentPage === 1}
                  onClick={() =>
                    setCurrentPage((prev) => Math.max(prev - 1, 1))
                  }
                  className="px-4 py-2 bg-white border rounded-xl disabled:opacity-50"
                >
                  Previous
                </button>

                <button
                  disabled={currentPage === totalPages}
                  onClick={() =>
                    setCurrentPage((prev) => Math.min(prev + 1, totalPages))
                  }
                  className="px-4 py-2 bg-white border rounded-xl disabled:opacity-50"
                >
                  Next
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};

export default AllMedicalRecords;

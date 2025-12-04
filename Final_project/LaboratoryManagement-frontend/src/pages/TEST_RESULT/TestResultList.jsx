import React, { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import {
  // removed DocumentText (not exported in your lucide-react)
  CheckCircle,
  Clock,
  Search,
  Eye,
  FileText,
} from "lucide-react";

export default function TestResultList() {
  const navigate = useNavigate();
  const [results, setResults] = useState([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState("");

  useEffect(() => {
    setTimeout(() => {
      setResults([
        {
          id: "1",
          testOrderId: "ORD-001",
          patientName: "John Doe",
          testType: "Blood Test",
          status: "completed",
          resultDate: new Date().toISOString(),
          result: "Normal",
        },
        {
          id: "2",
          testOrderId: "ORD-002",
          patientName: "Jane Smith",
          testType: "Urine Test",
          status: "completed",
          resultDate: new Date().toISOString(),
          result: "Abnormal",
        },
      ]);
      setLoading(false);
    }, 500);
  }, []);

  const getStatusBadge = (status) => {
    const statusLower = status?.toLowerCase() || "pending";
    const styles = {
      pending: "bg-amber-100 text-amber-700",
      completed: "bg-emerald-100 text-emerald-700",
      reviewed: "bg-blue-100 text-blue-700",
    };
    return styles[statusLower] || styles.pending;
  };

  const getResultBadge = (result) => {
    const resultLower = result?.toLowerCase() || "normal";
    const styles = {
      normal: "bg-emerald-100 text-emerald-700",
      abnormal: "bg-red-100 text-red-700",
      pending: "bg-amber-100 text-amber-700",
    };
    return styles[resultLower] || styles.normal;
  };

  const filteredResults = results.filter((result) => {
    const searchLower = searchTerm.toLowerCase();
    return (
      !searchTerm ||
      (result.testOrderId || "").toLowerCase().includes(searchLower) ||
      (result.patientName || "").toLowerCase().includes(searchLower)
    );
  });

  const completedCount = results.filter((r) => r.status === "completed").length;
  const pendingCount = results.filter((r) => r.status === "pending").length;

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-gradient-to-br from-gray-50 to-gray-100">
        <div className="text-center">
          <div className="inline-block animate-spin rounded-full h-16 w-16 border-4 border-emerald-200 border-t-emerald-600 mb-4"></div>
          <p className="text-gray-700 font-medium">Loading test results...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="p-6 bg-gradient-to-br from-gray-50 to-gray-100 min-h-screen">
      <div className="max-w-7xl mx-auto">
        <div className="mb-8">
          <div className="flex items-center gap-4 mb-3">
            <div className="w-12 h-12 rounded-2xl bg-gradient-to-br from-emerald-500 to-teal-500 flex items-center justify-center shadow-lg shadow-emerald-500/30">
              {/* replaced DocumentText with FileText */}
              <FileText className="w-6 h-6 text-white" />
            </div>
            <div>
              <h1 className="text-4xl font-bold text-gray-900">Test Results</h1>
              <p className="text-gray-500 mt-1">
                View and manage all laboratory test results
              </p>
            </div>
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
          {[
            {
              label: "Completed Results",
              value: completedCount,
              icon: CheckCircle,
              iconColor: "text-emerald-600",
              bgColor: "bg-emerald-50",
            },
            {
              label: "Pending Results",
              value: pendingCount,
              icon: Clock,
              iconColor: "text-amber-600",
              bgColor: "bg-amber-50",
            },
          ].map((stat, i) => {
            const IconComponent = stat.icon;
            return (
              <div
                key={i}
                className="bg-white rounded-2xl p-5 shadow-sm border border-gray-200 hover:shadow-xl transition-all duration-300 hover:-translate-y-1"
              >
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-gray-500 text-sm font-medium">
                      {stat.label}
                    </p>
                    <p className="text-3xl font-bold text-gray-900 mt-1">
                      {stat.value}
                    </p>
                  </div>
                  <div
                    className={`w-14 h-14 rounded-2xl ${stat.bgColor} flex items-center justify-center`}
                  >
                    <IconComponent className={`w-8 h-8 ${stat.iconColor}`} />
                  </div>
                </div>
              </div>
            );
          })}
        </div>

        <div className="bg-white rounded-3xl shadow-xl border border-gray-200 overflow-hidden">
          <div className="p-6 border-b border-gray-200 bg-gradient-to-r from-gray-50 to-white">
            <div className="relative group">
              <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-400 group-focus-within:text-emerald-500 transition-colors" />
              <input
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                placeholder="Search by order number or patient name..."
                className="w-full pl-12 pr-4 py-3.5 border-2 border-gray-200 rounded-2xl focus:outline-none focus:ring-2 focus:ring-emerald-500/20 focus:border-emerald-500 transition-all bg-white"
              />
            </div>
          </div>

          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="bg-gray-50">
                  <th className="text-left px-6 py-4 text-xs font-bold text-gray-600 uppercase tracking-wider">
                    Order #
                  </th>
                  <th className="text-left px-6 py-4 text-xs font-bold text-gray-600 uppercase tracking-wider">
                    Patient
                  </th>
                  <th className="text-left px-6 py-4 text-xs font-bold text-gray-600 uppercase tracking-wider">
                    Test Type
                  </th>
                  <th className="text-left px-6 py-4 text-xs font-bold text-gray-600 uppercase tracking-wider">
                    Status
                  </th>
                  <th className="text-left px-6 py-4 text-xs font-bold text-gray-600 uppercase tracking-wider">
                    Result
                  </th>
                  <th className="text-left px-6 py-4 text-xs font-bold text-gray-600 uppercase tracking-wider">
                    Result Date
                  </th>
                  <th className="text-center px-6 py-4 text-xs font-bold text-gray-600 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {filteredResults.length === 0 && (
                  <tr>
                    <td colSpan={7} className="px-6 py-20 text-center">
                      <div className="flex flex-col items-center gap-4">
                        <div className="w-20 h-20 rounded-full bg-gradient-to-br from-gray-100 to-gray-200 flex items-center justify-center">
                          {/* replaced DocumentText with FileText */}
                          <FileText className="w-10 h-10 text-gray-400" />
                        </div>
                        <div>
                          <div className="text-gray-700 font-semibold text-lg">
                            No test results found
                          </div>
                          <div className="text-sm text-gray-500 mt-1">
                            Try adjusting your search
                          </div>
                        </div>
                      </div>
                    </td>
                  </tr>
                )}
                {filteredResults.map((result, index) => (
                  <tr
                    key={result.id}
                    className="hover:bg-gradient-to-r hover:from-gray-50 hover:to-transparent transition-all duration-200 group"
                    style={{
                      animation: `slideUp 0.4s ease-out ${index * 0.05}s both`,
                    }}
                  >
                    <td className="px-6 py-5">
                      <span className="text-sm font-semibold text-emerald-600">
                        {result.testOrderId}
                      </span>
                    </td>
                    <td className="px-6 py-5">
                      <div className="text-sm font-medium text-gray-900">
                        {result.patientName}
                      </div>
                    </td>
                    <td className="px-6 py-5">
                      <div className="text-sm text-gray-700">
                        {result.testType}
                      </div>
                    </td>
                    <td className="px-6 py-5">
                      <span
                        className={`inline-flex items-center px-3 py-1 rounded-full text-xs font-medium ${getStatusBadge(
                          result.status
                        )}`}
                      >
                        {result.status || "Pending"}
                      </span>
                    </td>
                    <td className="px-6 py-5">
                      <span
                        className={`inline-flex items-center px-3 py-1 rounded-full text-xs font-medium ${getResultBadge(
                          result.result
                        )}`}
                      >
                        {result.result || "Pending"}
                      </span>
                    </td>
                    <td className="px-6 py-5">
                      <div className="text-sm text-gray-700">
                        {result.resultDate
                          ? new Date(result.resultDate).toLocaleDateString()
                          : "N/A"}
                      </div>
                    </td>
                    <td className="px-6 py-5">
                      <div className="flex items-center justify-center gap-1">
                        <button
                          onClick={() => navigate(`/test-results/${result.id}`)}
                          className="p-2.5 rounded-xl hover:bg-emerald-50 transition-all duration-200 group/btn hover:scale-110"
                          title="View result"
                        >
                          <Eye className="w-4 h-4 text-gray-400 group-hover/btn:text-emerald-600 transition-colors" />
                        </button>
                        <button
                          onClick={() =>
                            navigate(`/test-results/${result.id}/report`)
                          }
                          className="p-2.5 rounded-xl hover:bg-blue-50 transition-all duration-200 group/btn hover:scale-110"
                          title="Download report"
                        >
                          <FileText className="w-4 h-4 text-gray-400 group-hover/btn:text-blue-600 transition-colors" />
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <style>{`
        @keyframes slideUp {
          from { opacity: 0; transform: translateY(20px); }
          to { opacity: 1; transform: translateY(0); }
        }
      `}</style>
    </div>
  );
}

import React, { useEffect, useMemo, useState } from "react";
import { fetchPrivilegesPage } from "../../services/adminApi";
import PaginationControls from "../../components/PaginationControls";
import {
  Search,
  X,
  CheckCircle2,
  AlertCircle,
  Info,
  Shield,
  ShieldOff,
} from "lucide-react";
import { useTranslation } from "react-i18next";
import { useDebounce } from "../../hooks/useDebounce";

const getErrorMessage = (error, t) => {
  const errorCode =
    error?.response?.data?.code || error?.code || "UNKNOWN_ERROR";
  return t(`errors.${errorCode}`, { defaultValue: t("errors.UNKNOWN_ERROR") });
};

function Toast({ message, type = "success", onClose }) {
  React.useEffect(() => {
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
    <div className="fixed top-6 right-6 z-50 animate-slideIn font-sans">
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

function StatusBadge({ isActive }) {
  if (isActive) {
    return (
      <div className="inline-flex items-center gap-2 font-sans">
        <span className="relative flex h-3 w-3">
          <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
          <span className="relative inline-flex rounded-full h-3 w-3 bg-emerald-500"></span>
        </span>
        <span className="text-sm font-medium text-gray-700">Active</span>
      </div>
    );
  }
  return (
    <div className="inline-flex items-center gap-2 font-sans">
      <span className="relative flex h-3 w-3">
        <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-gray-400 opacity-75"></span>
        <span className="relative inline-flex rounded-full h-3 w-3 bg-gray-500"></span>
      </span>
      <span className="text-sm font-medium text-gray-700">Inactive</span>
    </div>
  );
}

function Loading({ size = 40 }) {
  return (
    <div className="flex items-center justify-center font-sans py-12">
      <div className="shapes-5" style={{ width: size, height: size }} />
    </div>
  );
}

export default function PrivilegesList() {
  const { t } = useTranslation();
  const [items, setItems] = useState([]);
  const [loading, setLoading] = useState(false);
  const [q, setQ] = useState("");
  const debouncedQ = useDebounce(q, 300);
  const [toast, setToast] = useState(null);

  const [page, setPage] = useState(0);
  const [size, setSize] = useState(10);
  const [totalElements, setTotalElements] = useState(0);
  const [totalPages, setTotalPages] = useState(1);

  async function loadFromServer(currentPage = 0, currentSize = 10, query = "") {
    setLoading(true);
    try {
      const params = {
        page: currentPage,
        size: currentSize,
      };
      if (query && query.trim() !== "") {
        params.q = query.trim();
      }
      const r = await fetchPrivilegesPage(params);
      let content = [];
      let total = 0;
      let pages = 1;
      if (Array.isArray(r)) {
        content = r;
        total = r.length;
        pages = 1;
      } else if (r && Array.isArray(r.content)) {
        content = r.content;
        total = r.totalElements || r.content.length;
        pages = r.totalPages || 1;
      } else if (r && Array.isArray(r.items)) {
        content = r.items;
        total = r.totalElements || r.items.length;
        pages = r.totalPages || 1;
      } else {
        content = [];
        total = 0;
        pages = 1;
      }
      setItems(content);
      setTotalElements(total);
      setTotalPages(pages || 1);
    } catch (err) {
      setToast({ message: getErrorMessage(err, t), type: "error" });
      setItems([]);
      setTotalElements(0);
      setTotalPages(1);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    loadFromServer(0, size, debouncedQ);
  }, []);

  useEffect(() => {
    setPage(0);
  }, [debouncedQ]);

  useEffect(() => {
    loadFromServer(page, size, debouncedQ);
  }, [page, size, debouncedQ]);

  // eslint-disable-next-line no-unused-vars
  const showToast = (message, type = "success") => {
    setToast({ message, type });
  };

  const activeCount = useMemo(
    () => items.filter((r) => r.isActive !== false).length,
    [items]
  );
  const inactiveCount = useMemo(
    () => items.filter((r) => r.isActive === false).length,
    [items]
  );

  const handlePageChange = (newPage) => {
    setPage(newPage);
  };

  const handleSizeChange = (newSize) => {
    setSize(newSize);
    setPage(0);
  };

  return (
    <div className="p-6 bg-gradient-to-br from-gray-50 via-white to-teal-50/30 min-h-screen font-sans">
      {toast && <Toast {...toast} onClose={() => setToast(null)} />}

      <div className="max-w-7xl mx-auto">
        <div className="mb-8">
          <div className="flex items-center gap-4 mb-3">
            <div className="w-12 h-12 rounded-2xl bg-gradient-to-br from-teal-500 to-emerald-500 flex items-center justify-center shadow-lg shadow-teal-500/30">
              <Shield className="w-6 h-6 text-white" />
            </div>
            <div>
              <h1 className="text-4xl font-bold text-gray-900">
                Privileges Management
              </h1>
              <p className="text-gray-500 mt-1">
                Manage privileges and permissions for the system
              </p>
            </div>
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
          {[
            {
              label: "Total Privileges",
              value: totalElements,
              icon: Shield,
              iconColor: "text-teal-600",
            },
            {
              label: "Active",
              value: activeCount,
              icon: CheckCircle2,
              iconColor: "text-emerald-600",
            },
            {
              label: "Inactive",
              value: inactiveCount,
              icon: ShieldOff,
              iconColor: "text-gray-600",
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
                  <div className="w-14 h-14 rounded-2xl bg-gray-50 flex items-center justify-center">
                    <IconComponent className={`w-8 h-8 ${stat.iconColor}`} />
                  </div>
                </div>
              </div>
            );
          })}
        </div>

        <div className="bg-white rounded-3xl shadow-xl border border-gray-200 overflow-hidden">
          <div className="p-6 border-b border-gray-200 bg-gradient-to-r from-gray-50 to-white">
            <div className="flex flex-col sm:flex-row gap-4 items-start sm:items-center justify-between">
              <div className="flex-1 w-full sm:w-auto">
                <div className="relative group">
                  <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-400 group-focus-within:text-teal-500 transition-colors" />
                  <input
                    value={q}
                    onChange={(e) => setQ(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") {
                        e.preventDefault();
                        loadFromServer(0, size, e.target.value);
                      }
                    }}
                    placeholder="Search by code, name or description..."
                    className="w-full pl-12 pr-4 py-3.5 border-2 border-gray-200 rounded-2xl focus:outline-none focus:ring-2 focus:ring-teal-500/20 focus:border-teal-500 transition-all bg-white"
                  />
                </div>
              </div>

              <div className="flex gap-3" />
            </div>
          </div>

          {loading ? (
            <div className="py-24">
              <Loading size={50} />
            </div>
          ) : (
            <>
              <div className="overflow-x-auto">
                <table className="w-full">
                  <thead>
                    <tr className="bg-gray-50">
                      <th className="text-left px-6 py-4 text-xs font-bold text-gray-600 uppercase tracking-wider">
                        Privilege Code
                      </th>
                      <th className="text-left px-6 py-4 text-xs font-bold text-gray-600 uppercase tracking-wider">
                        Privilege Name
                      </th>
                      <th className="text-left px-6 py-4 text-xs font-bold text-gray-600 uppercase tracking-wider">
                        Description
                      </th>
                      <th className="text-center px-6 py-4 text-xs font-bold text-gray-600 uppercase tracking-wider">
                        Status
                      </th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-100">
                    {items.map((p, index) => {
                      const isActive = p.isActive !== false;
                      return (
                        <tr
                          key={
                            p.id ||
                            p.code ||
                            p.privilegeId ||
                            `privilege-${index}`
                          }
                          className="hover:bg-gradient-to-r hover:from-teal-50/30 hover:to-transparent transition-all duration-200 group"
                          style={{
                            animation: `slideUp 0.4s ease-out ${
                              index * 0.03
                            }s both`,
                          }}
                        >
                          <td className="px-6 py-5">
                            <div className="font-mono text-sm font-semibold text-gray-900 group-hover:text-teal-600 transition-colors">
                              {p.code || p.id || p.privilegeCode}
                            </div>
                          </td>
                          <td className="px-6 py-5">
                            <div className="font-semibold text-gray-900">
                              {p.name || p.privilegeName}
                            </div>
                          </td>
                          <td className="px-6 py-5">
                            <div className="text-sm text-gray-500">
                              {p.description || p.privilegeDescription || "-"}
                            </div>
                          </td>
                          <td className="px-6 py-5">
                            <div className="flex justify-center">
                              <StatusBadge isActive={isActive} />
                            </div>
                          </td>
                        </tr>
                      );
                    })}

                    {items.length === 0 && (
                      <tr>
                        <td colSpan={4} className="px-6 py-20 text-center">
                          <div className="flex flex-col items-center gap-4">
                            <div className="w-20 h-20 rounded-full bg-gradient-to-br from-gray-100 to-gray-200 flex items-center justify-center">
                              <Shield className="w-10 h-10 text-gray-400" />
                            </div>
                            <div>
                              <div className="text-gray-700 font-semibold text-lg">
                                No privileges found
                              </div>
                              <div className="text-sm text-gray-500 mt-1">
                                Try changing your search keywords
                              </div>
                            </div>
                          </div>
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>

              <PaginationControls
                page={page}
                size={size}
                currentPageSize={items.length}
                totalElements={totalElements}
                totalPages={totalPages}
                onPageChange={handlePageChange}
                onSizeChange={handleSizeChange}
              />
            </>
          )}
        </div>
      </div>

      <style>{`
        @keyframes slideUp { from { opacity: 0; transform: translateY(20px); } to { opacity: 1; transform: translateY(0); } }
        @keyframes slideIn { from { opacity: 0; transform: translateX(100px); } to { opacity: 1; transform: translateX(0); } }
        .shapes-5 { width: 40px; aspect-ratio: 1; --c: no-repeat linear-gradient(#14b8a6 0 0); background: var(--c) 0% 100%, var(--c) 50% 100%, var(--c) 100% 100%; animation: sh5 1s infinite linear; }
        @keyframes sh5 { 0% {background-size:20% 100%,20% 100%,20% 100%} 33% {background-size:20% 10% ,20% 100%,20% 100%} 50% {background-size:20% 100%,20% 10% ,20% 100%} 66% {background-size:20% 100%,20% 100%,20% 10 } 100% {background-size:20% 100%,20% 100%,20% 100%} }
      `}</style>
    </div>
  );
}

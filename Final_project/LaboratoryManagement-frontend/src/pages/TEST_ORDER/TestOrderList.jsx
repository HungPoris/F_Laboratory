import React, { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import Swal from "sweetalert2";
import {
  ClipboardList,
  ClipboardCheck,
  Clock,
  Search,
  Filter,
  Plus,
  Edit3,
  Eye,
  Trash2,
  X,
} from "lucide-react";
import { fetchTestOrders, deleteTestOrder } from "../../services/testorderApi";

export default function TestOrderList() {
  const [orders, setOrders] = useState([]);
  const [pageInfo, setPageInfo] = useState({
    page: 0,
    size: 10,
    totalPages: 0,
  });
  const [loading, setLoading] = useState(true);
  // eslint-disable-next-line no-unused-vars
  const [filterOpen, setFilterOpen] = useState(false);
  const [searchTerm, setSearchTerm] = useState("");
  // eslint-disable-next-line no-unused-vars
  const [appliedFilters, setAppliedFilters] = useState({
    searchTerm: "",
    status: "all",
    priority: "all",
  });
  const navigate = useNavigate();

  const loadOrders = async (page = 0) => {
    try {
      setLoading(true);
      const data = await fetchTestOrders(page, pageInfo.size);

      setOrders(data.content || data.items || []);
      setPageInfo({
        page: data.number ?? data.page ?? page,
        size: data.size ?? pageInfo.size,
        totalPages: data.totalPages ?? data.total_pages ?? 1,
      });
    } catch (err) {
      console.error("Error loading test orders", err);
      Swal.fire("Error", "Failed to load test orders", "error");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadOrders(0);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const handleDelete = async (order) => {
    const orderId = order.id || order.orderId || order.testOrderId;

    if (!orderId) {
      Swal.fire("Error", "Invalid order ID", "error");
      return;
    }

    const confirm = await Swal.fire({
      icon: "warning",
      title: "Delete Test Order?",
      text: `Order ${
        order.orderNumber || orderId
      } will be permanently deleted.`,
      showCancelButton: true,
      confirmButtonText: "Yes, delete",
      confirmButtonColor: "#e11d48",
      cancelButtonColor: "#6b7280",
    });

    if (!confirm.isConfirmed) return;

    try {
      await deleteTestOrder(orderId);
      Swal.fire("Deleted", "Test order deleted successfully", "success");
      loadOrders(pageInfo.page);
    } catch (err) {
      console.error("Error deleting order", err);
      Swal.fire("Error", "Failed to delete test order", "error");
    }
  };

  const goPage = (p) => {
    if (p < 0 || p >= pageInfo.totalPages) return;
    loadOrders(p);
  };

  const getStatusBadge = (status) => {
    const statusLower = status?.toLowerCase() || "pending";
    const styles = {
      pending: "bg-amber-100 text-amber-700",
      in_progress: "bg-blue-100 text-blue-700",
      completed: "bg-emerald-100 text-emerald-700",
      cancelled: "bg-gray-100 text-gray-700",
    };
    return styles[statusLower] || styles.pending;
  };

  const getPriorityBadge = (priority) => {
    const priorityLower = priority?.toLowerCase() || "routine";
    const styles = {
      routine: "bg-slate-100 text-slate-700",
      urgent: "bg-orange-100 text-orange-700",
      stat: "bg-red-100 text-red-700",
    };
    return styles[priorityLower] || styles.routine;
  };

  const pendingCount = orders.filter(
    (o) => o.status?.toLowerCase() === "pending"
  ).length;
  const inProgressCount = orders.filter(
    (o) => o.status?.toLowerCase() === "in_progress"
  ).length;
  const completedCount = orders.filter(
    (o) => o.status?.toLowerCase() === "completed"
  ).length;

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-gradient-to-br from-gray-50 to-gray-100">
        <div className="text-center">
          <div className="inline-block animate-spin rounded-full h-16 w-16 border-4 border-cyan-200 border-t-cyan-600 mb-4"></div>
          <p className="text-gray-700 font-medium">Loading test orders...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="p-6 bg-gradient-to-br from-gray-50 to-gray-100 min-h-screen">
      <div className="max-w-7xl mx-auto">
        {/* Header */}
        <div className="mb-8">
          <div className="flex items-center gap-4 mb-3">
            <div className="w-12 h-12 rounded-2xl bg-gradient-to-br from-cyan-500 to-blue-500 flex items-center justify-center shadow-lg shadow-cyan-500/30">
              <ClipboardList className="w-6 h-6 text-white" />
            </div>
            <div>
              <h1 className="text-4xl font-bold text-gray-900">Test Orders</h1>
              <p className="text-gray-500 mt-1">
                Manage and track all laboratory test orders
              </p>
            </div>
          </div>
        </div>

        {/* Stats */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
          {[
            {
              label: "Pending Orders",
              value: pendingCount,
              icon: Clock,
              iconColor: "text-amber-600",
              bgColor: "bg-amber-50",
            },
            {
              label: "In Progress",
              value: inProgressCount,
              icon: ClipboardList,
              iconColor: "text-blue-600",
              bgColor: "bg-blue-50",
            },
            {
              label: "Completed",
              value: completedCount,
              icon: ClipboardCheck,
              iconColor: "text-emerald-600",
              bgColor: "bg-emerald-50",
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

        {/* Table Card */}
        <div className="bg-white rounded-3xl shadow-xl border border-gray-200 overflow-hidden">
          {/* Search Bar */}
          <div className="p-6 border-b border-gray-200 bg-gradient-to-r from-gray-50 to-white">
            <div className="flex flex-col sm:flex-row gap-4 items-start sm:items-center justify-between">
              <div className="flex-1 w-full sm:w-auto">
                <div className="relative group">
                  <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-400 group-focus-within:text-cyan-500 transition-colors" />
                  <input
                    value={searchTerm}
                    onChange={(e) => setSearchTerm(e.target.value)}
                    placeholder="Search by order number or patient name..."
                    className="w-full pl-12 pr-4 py-3.5 border-2 border-gray-200 rounded-2xl focus:outline-none focus:ring-2 focus:ring-cyan-500/20 focus:border-cyan-500 transition-all bg-white"
                  />
                </div>
              </div>

              <div className="flex gap-3">
                <button
                  onClick={() => navigate("/test-orders/new")}
                  className="px-6 py-3.5 rounded-2xl bg-gradient-to-r from-cyan-500 to-blue-500 hover:from-cyan-600 hover:to-blue-600 text-white font-semibold transition-all duration-200 flex items-center gap-2 shadow-lg shadow-cyan-500/40 hover:shadow-cyan-500/60 hover:-translate-y-0.5"
                >
                  <Plus className="w-5 h-5" />
                  <span>New Order</span>
                </button>
              </div>
            </div>
          </div>

          {/* Table */}
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="bg-gray-50">
                  <th className="text-left px-6 py-4 text-xs font-bold text-gray-600 uppercase">
                    Order #
                  </th>
                  <th className="text-left px-6 py-4 text-xs font-bold text-gray-600 uppercase">
                    Patient
                  </th>
                  <th className="text-left px-6 py-4 text-xs font-bold text-gray-600 uppercase">
                    Test Type
                  </th>
                  <th className="text-left px-6 py-4 text-xs font-bold text-gray-600 uppercase">
                    Status
                  </th>
                  <th className="text-left px-6 py-4 text-xs font-bold text-gray-600 uppercase">
                    Priority
                  </th>
                  <th className="text-left px-6 py-4 text-xs font-bold text-gray-600 uppercase">
                    Created Date
                  </th>
                  <th className="text-center px-6 py-4 text-xs font-bold text-gray-600 uppercase">
                    Actions
                  </th>
                </tr>
              </thead>

              <tbody className="divide-y divide-gray-100">
                {orders.length === 0 && (
                  <tr>
                    <td colSpan={7} className="px-6 py-20 text-center">
                      <div className="flex flex-col items-center gap-4">
                        <div className="w-20 h-20 rounded-full bg-gray-100 flex items-center justify-center">
                          <ClipboardList className="w-10 h-10 text-gray-400" />
                        </div>
                        <div>
                          <div className="text-gray-700 font-semibold text-lg">
                            No test orders found
                          </div>
                          <div className="text-sm text-gray-500 mt-1">
                            Get started by creating a new test order
                          </div>
                        </div>
                      </div>
                    </td>
                  </tr>
                )}

                {orders.map((order, index) => (
                  <tr
                    key={
                      order.id || order.orderId || order.testOrderId || index
                    }
                    className="hover:bg-gray-50 transition-all duration-200"
                    style={{
                      animation: `slideUp 0.4s ease-out ${index * 0.05}s both`,
                    }}
                  >
                    <td className="px-6 py-5">
                      <span className="text-sm font-semibold text-cyan-600">
                        {order.orderNumber ||
                          `ORD-${(order.id || "").substring(0, 8)}`}
                      </span>
                    </td>

                    <td className="px-6 py-5">
                      <div className="text-sm font-medium text-gray-900">
                        {order.patientName || "N/A"}
                      </div>
                    </td>

                    <td className="px-6 py-5">
                      <div className="text-sm text-gray-700">
                        {order.testType || "Blood Test"}
                      </div>
                    </td>

                    <td className="px-6 py-5">
                      <span
                        className={`inline-flex items-center px-3 py-1 rounded-full text-xs font-medium ${getStatusBadge(
                          order.status
                        )}`}
                      >
                        {order.status || "Pending"}
                      </span>
                    </td>

                    <td className="px-6 py-5">
                      <span
                        className={`inline-flex items-center px-3 py-1 rounded-full text-xs font-medium ${getPriorityBadge(
                          order.priority
                        )}`}
                      >
                        {order.priority || "Routine"}
                      </span>
                    </td>

                    <td className="px-6 py-5">
                      <div className="text-sm text-gray-700">
                        {order.createdAt
                          ? new Date(order.createdAt).toLocaleDateString()
                          : "N/A"}
                      </div>
                    </td>

                    <td className="px-6 py-5">
                      <div className="flex items-center justify-center gap-1">
                        <button
                          onClick={() => {
                            const orderId =
                              order.id || order.orderId || order.testOrderId;
                            if (orderId) navigate(`/test-orders/${orderId}`);
                          }}
                          className="p-2.5 rounded-xl hover:bg-cyan-50 transition-all duration-200"
                          title="View details"
                        >
                          <Eye className="w-4 h-4 text-gray-400 hover:text-cyan-600" />
                        </button>

                        <button
                          onClick={() => {
                            const orderId =
                              order.id || order.orderId || order.testOrderId;
                            if (orderId)
                              navigate(`/test-orders/${orderId}/edit`);
                          }}
                          className="p-2.5 rounded-xl hover:bg-blue-50 transition-all duration-200"
                          title="Edit order"
                        >
                          <Edit3 className="w-4 h-4 text-gray-400 hover:text-blue-600" />
                        </button>

                        <button
                          onClick={() => handleDelete(order)}
                          className="p-2.5 rounded-xl hover:bg-red-50 transition-all duration-200"
                          title="Delete order"
                        >
                          <Trash2 className="w-4 h-4 text-gray-400 hover:text-red-600" />
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* Pagination */}
          {pageInfo.totalPages > 1 && (
            <div className="bg-gray-50 px-6 py-4 border-t border-gray-200">
              <div className="flex flex-col sm:flex-row items-center justify-between gap-4">
                <div className="text-sm text-gray-600">
                  Page{" "}
                  <span className="font-semibold">{pageInfo.page + 1}</span> of{" "}
                  <span className="font-semibold">{pageInfo.totalPages}</span>
                </div>

                <nav className="flex items-center gap-2">
                  <button
                    onClick={() => goPage(pageInfo.page - 1)}
                    disabled={pageInfo.page <= 0}
                    className="px-4 py-2 text-sm font-medium bg-white border border-gray-300 rounded-xl hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    Previous
                  </button>

                  <button
                    onClick={() => goPage(pageInfo.page + 1)}
                    disabled={pageInfo.page >= pageInfo.totalPages - 1}
                    className="px-4 py-2 text-sm font-medium bg-white border border-gray-300 rounded-xl hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    Next
                  </button>
                </nav>
              </div>
            </div>
          )}
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

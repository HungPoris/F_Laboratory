import React, { useState, useEffect } from "react";
import { useParams, Link, useNavigate } from "react-router-dom";
import axios from "axios";
import Swal from "sweetalert2";
import {
  MessageSquare,
  Eye,
  Trash2,
  Plus,
  Edit3,
  ChevronLeft,
  ChevronRight,
} from "lucide-react";

import CommentModal from "../../components/CommentModal";
import PaginationControls from "../../components/PaginationControls";

const API_BASE =
  import.meta.env.VITE_API_TESTORDER_PATIENT || "https://be2.flaboratory.cloud";

function Avatar({ name = "", gender = "" }) {
  const initials = (name || "P").slice(0, 2).toUpperCase();
  const color =
    gender?.toLowerCase() === "male"
      ? "from-blue-400 to-blue-600"
      : gender?.toLowerCase() === "female"
      ? "from-pink-400 to-pink-600"
      : "from-purple-400 to-purple-600";

  return (
    <div
      className={`w-16 h-16 rounded-2xl bg-gradient-to-br ${color} flex items-center justify-center text-white text-xl font-bold shadow-lg`}
    >
      {initials}
    </div>
  );
}

const STATUS_ORDER = {
  PENDING: 1,
  IN_PROGRESS: 2,
  COMPLETED: 3,
  CANCELLED: 4,
};

const formatStatus = (status) => {
  switch (status) {
    case "PENDING":
      return "Pending";
    case "IN_PROGRESS":
      return "In progress";
    case "COMPLETED":
      return "Completed";
    case "CANCELLED":
      return "Cancelled";
    default:
      return status || "";
  }
};

export default function MedicalRecordView() {
  const { patientId, recordId } = useParams();
  const navigate = useNavigate();

  const [record, setRecord] = useState(null);
  const [patient, setPatient] = useState(null);
  const [loading, setLoading] = useState(true);

  const [testOrders, setTestOrders] = useState([]);
  const [allTestOrders, setAllTestOrders] = useState([]);
  const [loadingTests, setLoadingTests] = useState(false);

  const [sortStatus, setSortStatus] = useState("ALL");
  const [sortPriority, setSortPriority] = useState("ALL");

  const [page, setPage] = useState(0);
  const [totalPages, setTotalPages] = useState(0);
  const [totalElements, setTotalElements] = useState(0);
  const PAGE_SIZE = 10;

  const [openCommentModal, setOpenCommentModal] = useState(false);
  const [commentOrderId, setCommentOrderId] = useState(null);

  const callApi = async (endpoint, options = {}) => {
    const token = localStorage.getItem("lm.access");
    return axios({
      url: `${API_BASE}${endpoint}`,
      ...options,
      headers: {
        Authorization: token ? `Bearer ${token}` : undefined,
        "Content-Type": "application/json",
        ...options.headers,
      },
      withCredentials: true,
    });
  };

  useEffect(() => {
    loadPatient();
    loadRecord();
  }, [patientId, recordId]);

  useEffect(() => {
    if (recordId) loadTestOrders();
  }, [recordId]);

  const loadPatient = async () => {
    try {
      const res = await callApi(`/api/v1/patients/${patientId}`);
      setPatient(res.data);

      // eslint-disable-next-line no-unused-vars
    } catch (_) {
      /* empty */
    }
  };

  const loadRecord = async () => {
    try {
      setLoading(true);
      const res = await callApi(
        `/api/v1/patients/${patientId}/medical-records/${recordId}`
      );
      setRecord(res.data);
    } catch (error) {
      Swal.fire({
        icon: "error",
        title: "Error",
        text:
          error.response?.data?.message ||
          "Failed to load medical record details.",
      });
    } finally {
      setLoading(false);
    }
  };

  const handleDeleteRecord = async () => {
    const confirm = await Swal.fire({
      title: "Are you sure?",
      text: "This medical record will be permanently deleted.",
      icon: "warning",
      showCancelButton: true,
      confirmButtonColor: "#d33",
      cancelButtonColor: "#3085d6",
      confirmButtonText: "Yes, delete it",
    });

    if (!confirm.isConfirmed) return;

    try {
      await callApi(
        `/api/v1/patients/${patientId}/medical-records/${recordId}`,
        { method: "DELETE" }
      );

      Swal.fire({
        icon: "success",
        title: "Deleted!",
        text: "Medical record has been deleted.",
        timer: 1500,
      });

      navigate(`/patients/${patientId}`);
    } catch (err) {
      Swal.fire({
        icon: "error",
        title: "Failed",
        text: err.response?.data?.message || "Unable to delete medical record.",
      });
    }
  };

  const parseDepartments = () => {
    if (!record) return "N/A";

    if (typeof record.department === "string") {
      return record.department || "N/A";
    }
    if (Array.isArray(record.departments)) {
      return record.departments.length > 0
        ? record.departments.join(", ")
        : "N/A";
    }
    return "N/A";
  };

  const applyFiltersAndPagination = (
    sourceOrders,
    status = sortStatus,
    priority = sortPriority,
    pageIndex = page
  ) => {
    let filtered = [...sourceOrders];

    // FILTER STATUS
    if (status !== "ALL") {
      filtered = filtered.filter((o) => o.status === status);
    }

    // FILTER PRIORITY
    if (priority !== "ALL") {
      filtered = filtered.filter((o) => o.priority === priority);
    }

    // SORT
    filtered.sort((a, b) => {
      const sa = STATUS_ORDER[a.status] ?? 99;
      const sb = STATUS_ORDER[b.status] ?? 99;
      if (sa !== sb) return sa - sb;

      return new Date(b.createdAt) - new Date(a.createdAt);
    });

    // TOTAL ITEMS
    const total = filtered.length;

    // TOTAL PAGES
    const totalPagesCalc = Math.ceil(total / PAGE_SIZE);

    // PAGE SAFETY
    const safePage = Math.min(pageIndex, totalPagesCalc - 1);

    // CUT DATA
    const start = safePage * PAGE_SIZE;
    const paged = filtered.slice(start, start + PAGE_SIZE);

    // UPDATE STATE
    setTestOrders(paged);
    setTotalElements(total);
    setTotalPages(totalPagesCalc);
    setPage(safePage);
  };

  const loadTestOrders = async () => {
    try {
      setLoadingTests(true);
      const res = await callApi(
        `/api/v1/test-orders/by-medical-record/${recordId}`
      );

      const list = Array.isArray(res.data) ? res.data : res.data.items || [];
      setAllTestOrders(list);

      setSortStatus("ALL");
      setSortPriority("ALL");
      setPage(0);
      applyFiltersAndPagination(list, "ALL", "ALL", 0);

      // eslint-disable-next-line no-unused-vars
    } catch (_) {
      /* empty */
    } finally {
      setLoadingTests(false);
    }
  };

  const handleRequestTestOrder = () => {
    if (!record) return;

    const age =
      patient?.dob &&
      new Date().getFullYear() - new Date(patient.dob).getFullYear();

    navigate("/test-order/create", {
      state: {
        medicalRecordId: recordId,
        patientId,
        patientName: patient?.fullName,
        age,
        gender: patient?.gender,
        phoneNumber: patient?.contactNumber,
        email: patient?.email,
        address: patient?.address,
        dateOfBirth: patient?.dob,
        clinicalNotes: record?.clinicalNotes,
      },
    });
  };

  const handleSortStatus = (value) => {
    setSortStatus(value);
    applyFiltersAndPagination(allTestOrders, value, sortPriority, 0);
  };

  const handleSortPriority = (value) => {
    setSortPriority(value);
    applyFiltersAndPagination(allTestOrders, sortStatus, value, 0);
  };

  const handleViewComment = (orderId) => {
    setCommentOrderId(orderId);
    setOpenCommentModal(true);
  };

  const handleDeleteTestOrder = async (order) => {
    const confirm = await Swal.fire({
      title: `Delete Test Order?`,
      text: "This action cannot be undone.",
      icon: "warning",
      showCancelButton: true,
      confirmButtonColor: "#ef4444",
      cancelButtonColor: "#6b7280",
      confirmButtonText: "Delete",
    });

    if (!confirm.isConfirmed) return;

    try {
      await callApi(`/api/v1/test-orders/${order.id}`, {
        method: "DELETE",
      });

      Swal.fire("Deleted!", "Test order has been removed.", "success");

      loadTestOrders();
    } catch (err) {
      Swal.fire({
        icon: "error",
        title: "Error",
        text: err.response?.data?.message || "Failed to delete test order.",
      });
    }
  };

  const handleChangePage = (newPage) => {
    applyFiltersAndPagination(allTestOrders, sortStatus, sortPriority, newPage);
  };

  if (loading)
    return (
      <div className="flex items-center justify-center min-h-screen">
        Loading...
      </div>
    );

  if (!record) return <div className="p-10 text-center">Record not found.</div>;

  // eslint-disable-next-line no-unused-vars
  const currentPageNumber = page + 1;

  return (
    <div className="min-h-screen bg-gradient-to-br from-cyan-50 via-blue-50 to-teal-50">
      <div className="container mx-auto px-6 py-8">
        <Link
          to={`/patients/${patientId}`}
          className="inline-flex items-center text-cyan-600 hover:text-teal-600 font-medium mb-4"
        >
          ← Back to Patient Details
        </Link>

        <div className="bg-white rounded-lg shadow-md p-6 border-l-4 border-cyan-500 mb-8">
          <div className="flex items-center justify-between">
            <h1 className="text-3xl font-bold text-gray-900">
              Medical Record Details
            </h1>

            <div className="flex items-center gap-3">
              <button
                onClick={() =>
                  navigate(
                    `/patients/${patientId}/medical-records/${recordId}/edit`
                  )
                }
                className="inline-flex items-center gap-2 px-5 py-2 bg-teal-50 text-teal-600 rounded-md hover:bg-teal-100 transition-colors duration-150 font-medium"
              >
                <Edit3 className="w-5 h-5" /> Edit
              </button>

              <button
                onClick={handleDeleteRecord}
                className="inline-flex items-center gap-2 px-5 py-2 bg-red-50 text-red-600 rounded-md hover:bg-red-100 transition-colors duration-150 font-medium"
              >
                <Trash2 className="w-5 h-5" /> Delete
              </button>
            </div>
          </div>
        </div>

        <div className="bg-white rounded-lg shadow-md p-6 border-l-4 border-cyan-500 mb-8">
          <h2 className="text-xl font-semibold text-gray-800 mb-4 border-b pb-2">
            Patient Information
          </h2>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mb-8">
            <div>
              <label className="text-sm text-gray-500 font-medium mb-1 block">
                Full Name
              </label>
              <p className="text-gray-900 font-medium">
                {patient?.fullName || "N/A"}
              </p>
            </div>

            <div>
              <label className="text-sm text-gray-500 font-medium mb-1 block">
                Date of Birth
              </label>
              <p className="text-gray-900 font-medium">
                {patient?.dob
                  ? new Date(patient.dob).toISOString().slice(0, 10)
                  : "N/A"}
              </p>
            </div>

            <div>
              <label className="text-sm text-gray-500 font-medium mb-1 block">
                Gender
              </label>
              <p className="text-gray-900 font-medium">
                {patient?.gender || "N/A"}
              </p>
            </div>

            <div>
              <label className="text-sm text-gray-500 font-medium mb-1 block">
                Phone Number
              </label>
              <p className="text-gray-900 font-medium">
                {patient?.contactNumber || "N/A"}
              </p>
            </div>

            <div>
              <label className="text-sm text-gray-500 font-medium mb-1 block">
                Email
              </label>
              <p className="text-gray-900 font-medium">
                {patient?.email || "N/A"}
              </p>
            </div>

            <div>
              <label className="text-sm text-gray-500 font-medium mb-1 block">
                Address
              </label>
              <p className="text-gray-900 font-medium">
                {patient?.address || "N/A"}
              </p>
            </div>
          </div>

          <h2 className="text-xl font-semibold text-gray-800 mb-4 ">
            Record Information
          </h2>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            <div>
              <label className="text-sm text-gray-500 font-medium mb-1 block">
                Record Code
              </label>
              <p className="text-gray-900 font-medium">{record.recordCode}</p>
            </div>

            <div>
              <label className="text-sm text-gray-500 font-medium mb-1 block">
                Visit Date
              </label>
              <p className="text-gray-900 font-medium">
                {record.visitDate
                  ? new Date(record.visitDate).toLocaleString()
                  : "N/A"}
              </p>
            </div>

            <div>
              <label className="text-sm text-gray-500 font-medium mb-1 block">
                Chief Complaint
              </label>
              <p className="text-gray-900 font-medium">
                {record.chiefComplaint || "N/A"}
              </p>
            </div>

            <div>
              <label className="text-sm text-gray-500 font-medium mb-1 block">
                Departments
              </label>
              <p className="text-gray-900 font-medium">{parseDepartments()}</p>
            </div>
          </div>
        </div>

        <div className="mt-8 bg-white rounded-lg shadow-md p-6 border-l-4 border-cyan-500">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-xl font-semibold text-gray-800">Test Orders</h2>

            <div className="flex items-center gap-3">
              <button
                onClick={handleRequestTestOrder}
                className="inline-flex items-center gap-2 bg-gradient-to-r from-cyan-500 to-teal-500 text-white px-5 py-2 rounded-md hover:from-cyan-600 hover:to-teal-600 shadow-md hover:shadow-lg transition-all duration-200 font-medium"
              >
                <Plus className="w-5 h-5" />
                New Test Order
              </button>

              <button
                onClick={() => loadTestOrders()}
                className="inline-flex items-center gap-2 px-5 py-2 rounded-md border border-cyan-500 text-cyan-700 hover:bg-cyan-50 transition-colors duration-150 font-medium"
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
                    d="M4 4v5h.582m15.356 2A8 8 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8 8 0 01-15.357-2m15.357 2H15"
                  />
                </svg>
                Refresh
              </button>
            </div>
          </div>

          {loadingTests ? (
            <div className="text-center py-8">
              <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-cyan-600"></div>
              <p className="mt-2 text-gray-600">Loading test orders...</p>
            </div>
          ) : allTestOrders.length === 0 ? (
            <div className="text-center py-12 text-gray-500 font-medium">
              No test orders found.
            </div>
          ) : (
            <>
              {/* TABLE */}
              <div className="overflow-x-auto">
                <table className="min-w-full divide-y divide-gray-200">
                  <thead className="bg-gray-50">
                    <tr>
                      <th className="px-6 py-3 text-left text-xs font-semibold text-gray-600 uppercase">
                        Test Order
                      </th>

                      <th className="px-6 py-3 text-left text-xs font-semibold text-gray-600 uppercase">
                        <select
                          value={sortStatus}
                          onChange={(e) => handleSortStatus(e.target.value)}
                          className="border rounded-md px-2 py-1 text-xs bg-white cursor-pointer outline-none focus:ring-2 focus:ring-cyan-500"
                        >
                          <option value="ALL">Status</option>
                          <option value="PENDING">Pending</option>
                          <option value="IN_PROGRESS">In progress</option>
                          <option value="COMPLETED">Completed</option>
                          <option value="CANCELLED">Cancelled</option>
                        </select>
                      </th>

                      <th className="px-6 py-3 text-left text-xs font-semibold text-gray-600 uppercase">
                        <select
                          value={sortPriority}
                          onChange={(e) => handleSortPriority(e.target.value)}
                          className="border rounded-md px-2 py-1 text-xs bg-white cursor-pointer outline-none focus:ring-2 focus:ring-cyan-500"
                        >
                          <option value="ALL">Priority</option>
                          <option value="URGENT">Urgent</option>
                          <option value="HIGH">High</option>
                          <option value="NORMAL">Normal</option>
                          <option value="LOW">Low</option>
                        </select>
                      </th>

                      <th className="px-6 py-3 text-left text-xs font-semibold text-gray-600 uppercase">
                        Actions
                      </th>
                    </tr>
                  </thead>

                  <tbody className="bg-white divide-y divide-gray-100">
                    {testOrders.map((o) => (
                      <tr
                        key={o.id}
                        className="hover:bg-cyan-50 transition-colors duration-150"
                      >
                        <td className="px-6 py-4 text-sm font-semibold text-gray-700">
                          {o.orderNumber
                            ? `Test Order ${o.orderNumber}`
                            : `Order #${o.id}`}
                        </td>

                        <td className="px-6 py-4 text-sm">
                          <span
                            className={`px-3 py-1 rounded-full font-semibold text-xs
                      ${
                        o.status === "COMPLETED"
                          ? "bg-emerald-100 text-emerald-700"
                          : o.status === "IN_PROGRESS"
                          ? "bg-blue-100 text-blue-700"
                          : o.status === "CANCELLED"
                          ? "bg-red-100 text-red-700"
                          : "bg-slate-100 text-slate-700"
                      }`}
                          >
                            {formatStatus(o.status)}
                          </span>
                        </td>

                        <td className="px-6 py-4 text-sm">
                          <span
                            className={`px-3 py-1 rounded-full font-semibold text-xs
                      ${
                        o.priority === "URGENT" || o.priority === "STAT"
                          ? "bg-amber-100 text-amber-700"
                          : o.priority === "HIGH"
                          ? "bg-orange-100 text-orange-700"
                          : o.priority === "NORMAL"
                          ? "bg-green-100 text-green-700"
                          : "bg-slate-100 text-slate-700"
                      }`}
                          >
                            {o.priority}
                          </span>
                        </td>

                        <td className="px-6 py-4">
                          <div className="flex items-center gap-3">
                            <button
                              onClick={() => navigate(`/test-orders/${o.id}`)}
                              className="p-2 rounded-lg hover:bg-cyan-50 hover:scale-110 transition"
                            >
                              <Eye className="w-5 h-5 text-gray-500 hover:text-cyan-600" />
                            </button>

                            <button
                              onClick={() => handleViewComment(o.id)}
                              className="p-2 rounded-lg hover:bg-yellow-50 hover:scale-110 transition"
                            >
                              <MessageSquare className="w-5 h-5 text-gray-500 hover:text-yellow-600" />
                            </button>

                            <button
                              onClick={() => handleDeleteTestOrder(o)}
                              className="p-2 rounded-lg hover:bg-red-50 hover:scale-110 transition"
                            >
                              <Trash2 className="w-5 h-5 text-red-600 hover:text-red-700" />
                            </button>
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              {/* ✅ PaginationControls mới – luôn hiện, tự nhảy trang khi >10 items */}
              <PaginationControls
                page={page}
                size={PAGE_SIZE}
                currentPageSize={testOrders.length}
                totalElements={totalElements}
                totalPages={totalPages}
                onPageChange={handleChangePage}
              />
            </>
          )}
        </div>
      </div>

      <CommentModal
        open={openCommentModal}
        onClose={() => setOpenCommentModal(false)}
        itemId={commentOrderId}
      />
    </div>
  );
}

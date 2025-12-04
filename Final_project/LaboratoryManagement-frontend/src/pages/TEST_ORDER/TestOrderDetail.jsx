import React, { useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import {
  Edit3,
  MessageSquare,
  History,
  CheckCircle,
  XCircle,
  Trash2,
} from "lucide-react";

import Swal from "sweetalert2";
import {
  fetchTestOrderById,
  updateTestOrder,
  deleteTestOrder,
  deleteTestOrderItem,
} from "../../services/testorderApi";
import {
  createTestResult,
  fetchResultsByItemId,
  updateTestResult,
} from "../../services/testResultApi";
import AddItemModal from "../../components/AddItemModal";
import ViewResultModal from "../../components/ViewResultModal";
import CommentModal from "../../components/CommentModal";

const parseSnapshot = (snapshotData) => {
  if (!snapshotData) return null;
  if (typeof snapshotData === "object") return snapshotData;
  try {
    return JSON.parse(snapshotData);
  } catch (e) {
    console.error("Error parsing snapshot:", e);
    return null;
  }
};

export default function TestOrderDetail() {
  const { id } = useParams();
  const navigate = useNavigate();
  const testOrderId = id;

  const [order, setOrder] = useState(null);
  const [editing, setEditing] = useState(false);
  const [form, setForm] = useState({});
  const [loading, setLoading] = useState(true);
  const [loadingItems, setLoadingItems] = useState(false);
  const [inputValues, setInputValues] = useState({});
  const [openAddModal, setOpenAddModal] = useState(false);

  const [openViewModal, setOpenViewModal] = useState(false);
  const [viewItemId, setViewItemId] = useState(null);

  const [sortStatusAsc, setSortStatusAsc] = useState(true);
  const [sortFlag, setSortFlag] = useState("ALL");
  const [originalItems, setOriginalItems] = useState([]);
  const [editingItemId, setEditingItemId] = useState(null);

  const [openCommentModal, setOpenCommentModal] = useState(false);
  const [commentItemId, setCommentItemId] = useState(null);
  const [commentItemType, setCommentItemType] = useState("testOrder");

  const [itemResults, setItemResults] = useState({});



  const fetchItemResultValue = async (itemId) => {
    try {

      const results = await fetchResultsByItemId(itemId);
      if (results && results.length > 0) {
        return results[0].resultValue;
      }
      return null;
    } catch (err) {
      console.error(`Failed to fetch result for item ${itemId}:`, err);
      return null;
    }
  };



  const loadOrder = async () => {
    try {
      setLoading(true);
      const data = await fetchTestOrderById(testOrderId);

      setOrder(data);
      setOriginalItems(data.items ?? []);

      setForm({
        priority: data.priority,
        status: data.status,
      });


      const newResults = {};
      const completedItems = data.items.filter(
        (item) => item.status === "COMPLETED"
      );
      for (const item of completedItems) {
        const value = await fetchItemResultValue(item.id);
        newResults[item.id] = value;
      }
      setItemResults(newResults);
    } catch (err) {
      const msg =
        err.response?.data?.message ||
        err.message ||
        "Failed to load test order";
      Swal.fire("Error", msg, "error");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadOrder();
  }, [testOrderId]);

  const isPending = order?.status === "PENDING";
  const isInProgress = order?.status === "IN_PROGRESS";
  const isCompleted = order?.status === "COMPLETED";
  const isCancelled = order?.status === "CANCELLED";

  const allItemsCompleted =
    order?.items?.length > 0 &&
    order.items.every((item) => item.status === "COMPLETED");



  const snapshot = order ? parseSnapshot(order.medicalRecordSnapshot) : null;



  const handleChange = (e) => {
    const { name, value } = e.target;
    setForm((prev) => ({ ...prev, [name]: value }));
  };

  const handleSave = async () => {
    try {
      const payload = {
        ...order,
        priority: form.priority,
        status: form.status,
      };

      const updated = await updateTestOrder(order.id, payload);
      setOrder(updated);
      setEditing(false);

      Swal.fire("Success", "Test order updated", "success");
    // eslint-disable-next-line no-unused-vars
    } catch (err) {
      Swal.fire("Error", "Failed to update test order", "error");
    }
  };

  const handleConfirmComplete = async () => {
    const confirm = await Swal.fire({
      icon: "question",
      title: "Confirm Order Completion",
      text: "All test items are completed. Do you want to mark the order as COMPLETED?",
      showCancelButton: true,
      confirmButtonColor: "#10b981",
      cancelButtonColor: "#6b7280",
      confirmButtonText: "Yes, complete it",
    });

    if (!confirm.isConfirmed) return;

    try {
      const updated = await updateTestOrder(order.id, {
        ...order,
        status: "COMPLETED",
      });

      setOrder(updated);

      Swal.fire({
        icon: "success",
        title: "Order Completed",
        text: "The test order is now marked as COMPLETED.",
      });
    // eslint-disable-next-line no-unused-vars
    } catch (err) {
      Swal.fire("Error", "Failed to update order status", "error");
    }
  };



  const handleInputFocus = async (e) => {
    if (isPending) {
      e.target.blur();
      const confirm = await Swal.fire({
        title: "Start Analysis?",
        text: "The order is currently PENDING. Do you want to switch status to IN PROGRESS to enter results?",
        icon: "info",
        showCancelButton: true,
        confirmButtonText: "Yes, Start",
        confirmButtonColor: "#0ea5e9",
      });

      if (confirm.isConfirmed) {
        try {
          const payload = { ...order, status: "IN_PROGRESS" };
          const updated = await updateTestOrder(order.id, payload);
          setOrder(updated);
          Swal.fire(
            "Updated",
            "Order is now IN PROGRESS. You can enter results.",
            "success"
          );
        // eslint-disable-next-line no-unused-vars
        } catch (err) {
          Swal.fire("Error", "Failed to update status", "error");
        }
      }
    }
  };


  const handleDelete = async () => {
    const confirm = await Swal.fire({
      title: "Delete Test Order?",
      text: "This action cannot be undone.",
      icon: "warning",
      showCancelButton: true,
      confirmButtonColor: "#ef4444",
      cancelButtonColor: "#6b7280",
      confirmButtonText: "Yes, delete it",
    });

    if (!confirm.isConfirmed) return;

    try {
      await deleteTestOrder(order.id);
      await Swal.fire("Deleted!", "Test order deleted.", "success");
      navigate(
        `/patients/${order.patientId}/medical-records/${order.medicalRecordId}`
      );
    } catch (err) {
      console.error("Failed to delete test order", err);
      Swal.fire(
        "Error",
        err.response?.data?.message || "Failed to delete test order",
        "error"
      );
    }
  };


  const handleDeleteItem = async (itemId) => {
    const confirm = await Swal.fire({
      title: "Delete Test Item?",
      text: "This action cannot be undone.",
      icon: "warning",
      showCancelButton: true,
      confirmButtonColor: "#ef4444",
      cancelButtonColor: "#6b7280",
      confirmButtonText: "Yes, delete it",
    });

    if (!confirm.isConfirmed) return;

    try {

      await deleteTestOrderItem(itemId);

      Swal.fire("Deleted!", "Test item removed.", "success");

      await loadOrder();
    // eslint-disable-next-line no-unused-vars
    } catch (err) {
      Swal.fire("Error", "Failed to delete item", "error");
    }
  };



  const handleRefreshItems = async () => {
    try {
      setLoadingItems(true);
      const data = await fetchTestOrderById(testOrderId);
      setOrder(data);
      setOriginalItems(data.items ?? []);


      const newResults = {};
      const completedItems = data.items.filter(
        (item) => item.status === "COMPLETED"
      );
      for (const item of completedItems) {
        const value = await fetchItemResultValue(item.id);
        newResults[item.id] = value;
      }
      setItemResults(newResults);

      Swal.fire({
        icon: "success",
        title: "Refreshed!",
        timer: 1000,
        showConfirmButton: false,
      });
    } catch {
      Swal.fire("Error", "Failed to refresh items", "error");
    } finally {
      setLoadingItems(false);
    }
  };



  const handleViewItem = (itemId) => {
    setViewItemId(itemId);
    setOpenViewModal(true);
  };

  const handleComment = (id, type = "testResult") => {
    setCommentItemId(id);
    setCommentItemType(type);
    setOpenCommentModal(true);
  };



  const handleCreateResult = async (itemId) => {
    const value = inputValues[itemId];
    if (!value) {
      Swal.fire("Warning", "Please enter a value", "warning");
      return;
    }
    try {
      const payload = {
        testOrderItemId: itemId,
        resultValue: Number(value),
      };
      await createTestResult(payload);
      await loadOrder();
      setInputValues((prev) => ({ ...prev, [itemId]: "" }));
      setEditingItemId(null);
    } catch (err) {
      Swal.fire(
        "Error",
        err.response?.data?.message || "Failed to create result",
        "error"
      );
    }
  };



  const handleStartEdit = (item) => {
    if (item.status === "COMPLETED" && isInProgress) {

      setEditingItemId(item.id);


      const currentValue = itemResults[item.id] || "";
      setInputValues((prev) => ({
        ...prev,
        [item.id]: currentValue,
      }));
    }
  };

  const handleCancelEdit = (itemId) => {
    setInputValues((prev) => ({ ...prev, [itemId]: "" }));
    setEditingItemId(null);
  };

  const handleSaveEdit = async (item) => {
    const value = inputValues[item.id];
    if (value === undefined || value === "") {
      Swal.fire("Warning", "Please enter a value", "warning");
      return;
    }
    try {

      const results = await fetchResultsByItemId(item.id);
      if (!results || results.length === 0) {
        Swal.fire("Error", "Result not found for this item", "error");
        return;
      }

      const resultId = results[0].id;


      const payload = {
        resultValue: Number(value),
      };
      await updateTestResult(resultId, payload);


      await loadOrder();
      setInputValues((prev) => ({ ...prev, [item.id]: "" }));
      setEditingItemId(null);
    } catch (err) {
      Swal.fire(
        "Error",
        err.response?.data?.message || "Failed to update result",
        "error"
      );
    }
  };




  if (loading) {

    return (
      <div className="flex items-center justify-center min-h-screen bg-gradient-to-br from-cyan-50 via-blue-50 to-teal-50">
        <div className="text-center">
          <div className="inline-block animate-spin rounded-full h-16 w-16 border-4 border-cyan-200 border-t-cyan-600 mb-4" />
          <p className="text-gray-700 font-medium">Loading test order...</p>
        </div>
      </div>
    );
  }

  if (!order) {

    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="text-center">
          <p className="text-gray-700 mb-3">Test order not found</p>
          <button
            onClick={() => navigate("/lab-manager/testorders")}
            className="text-cyan-600 hover:text-teal-600 font-medium"
          >
            ← Back to Test Orders
          </button>
        </div>
      </div>
    );
  }

  const canEditOrderInfo = !isInProgress && !isCompleted && !isCancelled;
  const canAddItem = isPending;
  const canRefresh = !isCompleted && !isCancelled;
  const canEditResult = isInProgress;

  return (
    <div className="min-h-screen bg-gradient-to-br from-cyan-50 via-blue-50 to-teal-50">
      <div className="container mx-auto px-6 py-8">

        <button
          onClick={() =>
            navigate(
              `/patients/${order.patientId}/medical-records/${order.medicalRecordId}`
            )
          }
          className="inline-flex items-center text-cyan-600 hover:text-teal-600 font-medium mb-5"
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
          Back to Medical Record
        </button>


        <div className="bg-white rounded-lg shadow-md p-6 border-l-4 border-cyan-500 mb-8">
          <div className="flex justify-between items-center">
            <h1 className="text-3xl font-bold text-gray-800">
              Test Order {order.orderNumber || order.id}
            </h1>
            <div className="flex items-center gap-3">
              <button
                disabled={!canEditOrderInfo}
                onClick={() => canEditOrderInfo && setEditing((v) => !v)}
                className={`inline-flex items-center gap-2 px-5 py-2 rounded-md font-medium transition
                  ${
                    !canEditOrderInfo
                      ? "bg-gray-300 text-gray-500 cursor-not-allowed"
                      : "bg-teal-50 text-teal-600 hover:bg-teal-100"
                  }
                `}
              >
                <Edit3 className="w-5 h-5" />
                {editing ? "Cancel" : "Edit"}
              </button>

              <button
                disabled={isInProgress}
                onClick={!isInProgress ? handleDelete : undefined}
                className={`inline-flex items-center gap-2 px-5 py-2 rounded-md font-medium
                  ${
                    isInProgress
                      ? "bg-gray-300 text-gray-400 cursor-not-allowed"
                      : "bg-red-50 text-red-600 hover:bg-red-100"
                  }
                  `}
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
                    d="M19 7l-.867 12.142A2 2 0
                    0116.138 21H7.862a2 2 0
                    01-1.995-1.858L5
                    7m5 4v6m4-6v6m1-10V4a1 1 0
                    00-1-1H9a1 1 0 00-1 1v3M4 7h16"
                  />
                </svg>
                Delete
              </button>
            </div>
          </div>
        </div>


        <div className="bg-white rounded-lg shadow-md p-6 mb-8 border-l-4 border-cyan-500">
          <h2 className="text-xl font-semibold text-gray-800 mb-4 border-b pb-2">
            Order Information
          </h2>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-4 text-sm">

            <div>
              <div className="text-gray-500 mb-1">Status</div>
              {editing ? (
                <select
                  name="status"
                  value={form.status}
                  onChange={handleChange}
                  className="w-full border rounded-lg px-3 py-2"
                >
                  <option value="PENDING">PENDING</option>
                  <option value="IN_PROGRESS">IN PROGRESS</option>
                  <option value="COMPLETED">COMPLETED</option>
                  <option value="CANCELLED">CANCELLED</option>
                </select>
              ) : (
                <span
                  className={`inline-flex items-center px-3 py-1 rounded-full text-sm font-semibold
                    ${
                      order.status === "PENDING"
                        ? "bg-slate-200 text-slate-700"
                        : order.status === "IN_PROGRESS"
                        ? "bg-blue-200 text-blue-800"
                        : order.status === "COMPLETED"
                        ? "bg-emerald-200 text-emerald-800"
                        : "bg-red-200 text-red-800"
                    }
                  `}
                >
                  {order.status}
                </span>
              )}
            </div>

            <div>
              <div className="text-gray-500 mb-1">Priority</div>
              {editing ? (
                <select
                  name="priority"
                  value={form.priority}
                  onChange={handleChange}
                  className="w-full border rounded-lg px-3 py-2"
                >
                  <option value="NORMAL">NORMAL</option>
                  <option value="URGENT">URGENT</option>
                  <option value="STAT">STAT</option>
                </select>
              ) : (
                <span
                  className={`inline-flex items-center px-3 py-1 rounded-full font-semibold
                    ${
                      order.priority === "STAT"
                        ? "bg-red-100 text-red-700"
                        : order.priority === "URGENT"
                        ? "bg-amber-100 text-amber-700"
                        : "bg-emerald-100 text-emerald-700"
                    }
                  `}
                >
                  {order.priority}
                </span>
              )}
            </div>

            <div>
              <div className="text-gray-500 mb-1">Created At</div>
              <div className="font-medium text-gray-800">
                {order.createdAt
                  ? new Date(order.createdAt).toLocaleString()
                  : "N/A"}
              </div>
            </div>


            <div className="md:col-span-3 border-t pt-4 grid grid-cols-1 md:grid-cols-3 gap-4 text-sm">

                <div>
                    <div className="text-gray-500 mb-1">Patient</div>
                    <div className="font-medium text-gray-800">
                        {order.patientName || "N/A"}
                    </div>
                </div>

                <div>
                    <div className="text-gray-500 mb-1">Age / Gender</div>
                    <div className="font-medium text-gray-800">
                        {order.age ?? "N/A"} / {order.gender || "N/A"}
                    </div>
                </div>

                <div>
                    <div className="text-gray-500 mb-1">Phone</div>
                    <div className="font-medium text-gray-800">
                        {order.phoneNumber || "N/A"}
                    </div>
                </div>
            </div>
          </div>

          {editing && (
            <div className="flex justify-end mt-4">
              <button
                onClick={handleSave}
                className="px-5 py-2 rounded-md text-white font-semibold bg-gradient-to-r from-cyan-500 to-teal-500"
              >
                Save Changes
              </button>
            </div>
          )}


          {snapshot && (
            <div className="mt-8 border-t border-dashed border-gray-300 pt-6">
              <div className="bg-purple-50 rounded-lg p-5 border border-purple-200">
                <div className="flex items-center gap-2 mb-3">
                  <History className="w-5 h-5 text-purple-600" />
                  <h3 className="text-lg font-semibold text-gray-800">
                    Medical Record Snapshot
                  </h3>
                  <span className="text-xs text-gray-500 font-normal">
                    (Captured at time of order)
                  </span>
                </div>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-x-6 gap-y-4 text-sm">
                  {[
                    ["Record Code", snapshot.recordCode],
                    [
                      "Visit Date",
                      snapshot.visitDate
                        ? new Date(snapshot.visitDate).toLocaleString()
                        : "N/A",
                    ],
                    ["Diagnosis", snapshot.diagnosis],
                    ["Chief Complaint", snapshot.chiefComplaint],
                    ["Prescriptions", snapshot.prescriptions],
                    ["Attending Physician", snapshot.attendingPhysician],
                  ].map(
                    ([label, value]) =>
                      value && (
                        <div key={label}>
                          <label className="block text-xs font-semibold text-purple-700 mb-0.5">
                            {label}
                          </label>
                          <p className="text-gray-900 font-medium whitespace-pre-wrap">
                            {value}
                          </p>
                        </div>
                      )
                  )}
                </div>

                <div className="mt-4 pt-3 border-t border-purple-100 text-xs text-purple-600 italic flex items-center">
                  <svg
                    className="w-3 h-3 mr-1.5"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth={2}
                      d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                  Historical data. Updates to original record are not reflected
                  here.
                </div>
              </div>
            </div>
          )}
        </div>


        <div className="bg-white rounded-lg shadow-md p-6 border-l-4 border-cyan-500">
          <div className="flex items-center justify-between mb-6">
            <h2 className="text-xl font-semibold text-gray-800">
              Test Order Items
            </h2>

            <div className="flex items-center gap-3">

              <button
                disabled={!canAddItem}
                onClick={() => canAddItem && setOpenAddModal(true)}
                title={
                  !canAddItem
                    ? "You can only add items when the order is PENDING"
                    : ""
                }
                className={`inline-flex items-center gap-2 px-5 py-2 rounded-md font-medium transition-all duration-200
                  ${
                    !canAddItem
                      ? "bg-gray-300 text-gray-500 cursor-not-allowed"
                      : "bg-gradient-to-r from-cyan-500 to-teal-500 text-white hover:from-cyan-600 hover:to-teal-600 shadow-md"
                  }
                `}
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
                Add Item
              </button>


              {allItemsCompleted && !isCompleted && !isCancelled && (
                <button
                  onClick={handleConfirmComplete}
                  className="inline-flex items-center gap-2 px-5 py-2 rounded-md font-semibold shadow-md
                    bg-emerald-500 text-white hover:bg-emerald-600 transition"
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
                      d="M5 13l4 4L19 7"
                    />
                  </svg>
                  Confirm Complete
                </button>
              )}


              <button
                disabled={!canRefresh}
                onClick={canRefresh ? handleRefreshItems : undefined}
                className={`inline-flex items-center gap-2 px-5 py-2 rounded-md border font-medium
                    ${
                      !canRefresh
                        ? "text-gray-400 border-gray-300 cursor-not-allowed"
                        : "border-cyan-500 text-cyan-700 hover:bg-cyan-50"
                    }
                `}
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
                    d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11
                    11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
                  />
                </svg>
                Refresh
              </button>
            </div>
          </div>

          {loadingItems ? (
            <div className="py-10 text-center">
              <div className="inline-block animate-spin h-8 w-8 border-b-2 border-cyan-600 rounded-full"></div>
            </div>
          ) : !order.items || order.items.length === 0 ? (
            <div className="text-center text-gray-500 py-12">
              No items added yet.
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="min-w-full divide-y divide-gray-200">
                <thead className="bg-gray-50">
                  <tr>
                    <th className="px-6 py-3 text-left text-xs font-semibold text-gray-600 uppercase">
                      Test Code
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-semibold text-gray-600 uppercase">
                      Test Name
                    </th>

                    <th
                      className="px-6 py-3 text-left text-xs font-semibold text-gray-600 uppercase cursor-pointer select-none"
                      onClick={() => {
                        const map = {
                          PENDING: 1,
                          IN_PROGRESS: 2,
                          COMPLETED: 3,
                        };

                        const sorted = [...originalItems].sort((a, b) => {
                          return sortStatusAsc
                            ? map[a.status] - map[b.status]
                            : map[b.status] - map[a.status];
                        });
                        setSortStatusAsc(!sortStatusAsc);
                        setOrder({ ...order, items: sorted });
                      }}
                    >
                      Status {sortStatusAsc ? "▲" : "▼"}
                    </th>

                    <th className="px-6 py-3 text-left text-xs font-semibold text-gray-600 uppercase">
                      Result
                    </th>

                    <th className="px-6 py-3 text-left text-xs font-semibold text-gray-600 uppercase">
                      <select
                        className="border rounded-md px-2 py-1 text-xs bg-white"
                        value={sortFlag}
                        onChange={(e) => {
                          const value = e.target.value;
                          setSortFlag(value);

                          if (value === "ALL") {
                            setOrder({ ...order, items: originalItems });
                            return;
                          }
                          let map = {};
                          if (value === "HIGH")
                            map = { HIGH: 1, NORMAL: 2, LOW: 3 };
                          if (value === "NORMAL")
                            map = { NORMAL: 1, HIGH: 2, LOW: 3 };
                          if (value === "LOW")
                            map = { LOW: 1, NORMAL: 2, HIGH: 3 };

                          const exists = originalItems.some(
                            (x) => x.flagType === value
                          );
                          if (!exists) {
                            Swal.fire({
                              icon: "error",
                              title: "No results found",
                              text: `There are no test items with result: ${value}`,
                              confirmButtonColor: "#ef4444",
                            });
                            return;
                          }
                          const sorted = [...originalItems].sort((a, b) => {
                            const va = map[a.flagType] || 99;
                            const vb = map[b.flagType] || 99;
                            return va - vb;
                          });

                          setOrder({ ...order, items: sorted });
                        }}
                      >
                        <option value="ALL">Flag</option>
                        <option value="HIGH">High First</option>
                        <option value="NORMAL">Normal First</option>
                        <option value="LOW">Low First</option>
                      </select>
                    </th>

                    <th className="px-6 py-3 text-left text-xs font-semibold text-gray-600 uppercase">
                      Actions
                    </th>
                  </tr>
                </thead>
                <tbody className="bg-white divide-y divide-gray-100">
                  {order.items.map((item) => {
                    const isEditing = editingItemId === item.id;
                    const isCompletedItem = item.status === "COMPLETED";

                    return (
                      <tr
                        key={item.id}
                        className="hover:bg-cyan-50 transition-colors"
                      >
                        <td className="px-6 py-4 text-sm font-semibold">
                          {item.testTypeCode}
                        </td>
                        <td className="px-6 py-4 text-sm">
                          {item.testTypeName}
                        </td>


                        <td className="px-6 py-4">
                          <span
                            className={`inline-flex items-center px-2 py-1 rounded-full text-xs font-semibold
                              ${
                                item.status === "COMPLETED"
                                  ? "bg-emerald-100 text-emerald-700"
                                  : item.status === "IN_PROGRESS"
                                  ? "bg-blue-100 text-blue-700"
                                  : "bg-slate-100 text-slate-700"
                              }
                            `}
                          >
                            {item.status}
                          </span>
                        </td>


                        <td className="px-6 py-4">
                          {isCompletedItem && !isEditing ? (
                            <span className="px-2 py-1 text-sm font-medium text-gray-800">
                              {itemResults[item.id] !== null &&
                              itemResults[item.id] !== undefined
                                ? itemResults[item.id]
                                : "N/A"}
                            </span>
                          ) : (
                            <input
                              type="number"
                              placeholder="Value"
                              disabled={isCancelled || isCompleted}
                              readOnly={!isInProgress}
                              onClick={
                                !isCompletedItem ? handleInputFocus : undefined
                              }
                              onFocus={
                                !isCompletedItem ? handleInputFocus : undefined
                              }
                              value={inputValues[item.id] || ""}
                              onChange={(e) => {
                                if (!isInProgress) return;
                                setInputValues((prev) => ({
                                  ...prev,
                                  [item.id]: e.target.value,
                                }));
                              }}
                              onKeyDown={(e) => {
                                if (e.key === "Enter" && isInProgress) {
                                  if (isEditing) {
                                    handleSaveEdit(item);
                                  } else if (!isCompletedItem) {
                                    handleCreateResult(item.id);
                                  }
                                }
                              }}
                              className={`w-24 px-2 py-1 border rounded-md text-sm transition-colors
                                ${
                                  isInProgress
                                    ? "bg-white border-gray-300"
                                    : "bg-gray-100 cursor-pointer"
                                }
                              `}
                            />
                          )}
                        </td>


                        <td className="px-6 py-4">
                          {item.status === "COMPLETED" ? (
                            <span
                              className={`px-2 py-1 rounded-full text-xs font-semibold
                                ${
                                  item.flagType === "HIGH"
                                    ? "bg-red-100 text-red-700"
                                    : item.flagType === "LOW"
                                    ? "bg-amber-100 text-amber-700"
                                    : "bg-emerald-100 text-emerald-700"
                                }
                              `}
                            >
                              {item.flagType || "NORMAL"}
                            </span>
                          ) : (
                            <span className="text-xs text-gray-500">N/A</span>
                          )}
                        </td>


                        <td className="px-6 py-4">
                          <div className="flex items-center gap-3">

                            <button
                              onClick={() => handleViewItem(item.id)}
                              className="p-2 rounded-lg hover:bg-cyan-50 hover:scale-110 transition"
                              title="View"
                            >
                              <svg
                                xmlns="http://www.w3.org/2000/svg"
                                className="w-5 h-5 text-gray-500 hover:text-cyan-600"
                                fill="none"
                                viewBox="0 0 24 24"
                                stroke="currentColor"
                                strokeWidth={2}
                              >
                                <path
                                  strokeLinecap="round"
                                  strokeLinejoin="round"
                                  d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
                                />
                                <path
                                  strokeLinecap="round"
                                  strokeLinejoin="round"
                                  d="M2.458 12C3.732 7.943 7.523 5 12 5s8.268 2.943 9.542 7c-1.274 4.057-5.065 7-9.542 7S3.732 16.057 2.458 12z"
                                />
                              </svg>
                            </button>


                            {isPending && (
                              <button
                                onClick={() => handleDeleteItem(item.id)}

                                className="p-2 rounded-lg hover:bg-red-50 hover:scale-110 transition"
                                title="Delete"
                              >
                                <Trash2 className="w-5 h-5 text-red-600 hover:text-red-700" />
                              </button>
                            )}


                            {isCompletedItem && !isEditing && (
                              <button
                                onClick={() => handleStartEdit(item)}
                                disabled={!canEditResult}
                                className={`p-2 rounded-lg transition ${
                                  !canEditResult
                                    ? "opacity-40 cursor-not-allowed"
                                    : "hover:bg-amber-50 hover:scale-110"
                                }`}
                                title="Edit Result"
                              >
                                <Edit3 className="w-5 h-5 text-gray-500 hover:text-amber-600" />
                              </button>
                            )}

                            {isEditing && (
                              <>
                                <button
                                  onClick={() => handleSaveEdit(item)}
                                  className="p-2 rounded-lg text-emerald-500 hover:bg-emerald-50 hover:scale-110"
                                  title="Save Result"
                                >
                                  <CheckCircle className="w-5 h-5" />
                                </button>
                                <button
                                  onClick={() => handleCancelEdit(item.id)}
                                  className="p-2 rounded-lg text-red-500 hover:bg-red-50 hover:scale-110"
                                  title="Cancel Edit"
                                >
                                  <XCircle className="w-5 h-5" />
                                </button>
                              </>
                            )}


                            <button
                              onClick={() =>
                                handleComment(item.id, "testResult")
                              }
                              disabled={isCancelled}
                              className={`p-2 rounded-lg transition ${
                                isCancelled
                                  ? "opacity-40 cursor-not-allowed"
                                  : "hover:bg-yellow-50 hover:scale-110"
                              }`}
                              title="Comment"
                            >
                              <MessageSquare className="w-5 h-5 text-gray-500 hover:text-yellow-600" />
                            </button>
                          </div>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>


      <AddItemModal
        open={openAddModal}
        onClose={() => setOpenAddModal(false)}
        order={order}
        onAdded={() => loadOrder()}
      />

      <ViewResultModal
        open={openViewModal}
        onClose={() => setOpenViewModal(false)}
        itemId={viewItemId}
      />

      <CommentModal
        open={openCommentModal}
        onClose={() => setOpenCommentModal(false)}
        itemId={commentItemId}
        itemType={commentItemType}
      />
    </div>
  );
}
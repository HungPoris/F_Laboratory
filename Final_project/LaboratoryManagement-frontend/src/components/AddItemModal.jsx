import React, { useEffect, useState } from "react";
import axios from "axios";
import Swal from "sweetalert2";

const API_BASE = import.meta.env.VITE_API_TESTORDER || "https://be2.flaboratory.cloud";

export default function AddItemModal({ open, onClose, order, onAdded }) {
  const [testTypes, setTestTypes] = useState([]);
  const [loading, setLoading] = useState(false);
  const [selected, setSelected] = useState([]);

  const existing = new Set(order.items.map((i) => i.testTypeId)); // test đã có

  useEffect(() => {
    if (open) loadTestTypes();
  }, [open]);

  const loadTestTypes = async () => {
    try {
      setLoading(true);

      const token = localStorage.getItem("lm.access");

      const res = await axios.get(`${API_BASE}/api/v1/test-types`, {
        headers: { Authorization: token ? `Bearer ${token}` : undefined },
        withCredentials: true,
      });

      setTestTypes(Array.isArray(res.data) ? res.data : []);
    } catch (err) {
      Swal.fire("Error", "Failed to load test types", "error");
    } finally {
      setLoading(false);
    }
  };

  const toggle = (id) => {
    setSelected((prev) =>
      prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]
    );
  };

  // ⭐⭐ API sửa đúng theo BE: POST /test-orders/{id}/add-items
  const handleSubmit = async () => {
    if (selected.length === 0) {
      Swal.fire("Missing", "Please select at least one test type", "warning");
      return;
    }

    try {
      const token = localStorage.getItem("lm.access");

      const payload = {
        testTypeIds: selected,
      };

      await axios.post(
        `${API_BASE}/api/v1/test-orders/${order.id}/add-items`,
        payload,
        {
          headers: { Authorization: token ? `Bearer ${token}` : undefined },
          withCredentials: true,
        }
      );

      Swal.fire("Success", "Items added", "success");

      onAdded(); 
      onClose();
    } catch (err) {
      console.error(err);
      Swal.fire("Error", err.response?.data?.message || "Failed", "error");
    }
  };

  if (!open) return null;

  return (
    <div
      className="
        fixed inset-0 z-50 flex justify-center items-center
        backdrop-blur-sm bg-white/20
        transition-all duration-300
      "
    >
      <div
        className="
          bg-white rounded-xl shadow-xl p-6 w-full max-w-lg
          animate-fadeIn
        "
        style={{ animation: "fadeIn 0.2s ease-out" }}
      >
        <h2 className="text-xl font-semibold mb-4">Add Test Items</h2>

        {loading ? (
          <p>Loading...</p>
        ) : (
          <div className="max-h-64 overflow-y-auto border rounded-lg p-3 space-y-2">
            {testTypes.map((tt) => {
              const disabled = existing.has(tt.id);
              return (
                <label key={tt.id} className="flex items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    disabled={disabled}
                    checked={selected.includes(tt.id)}
                    onChange={() => toggle(tt.id)}
                    className="rounded border-gray-300"
                  />
                  <span className={disabled ? "text-gray-400" : "text-gray-800"}>
                    <strong>{tt.code}</strong> - {tt.name}
                    {disabled && (
                      <span className="ml-1 text-xs text-red-400">
                        (already added)
                      </span>
                    )}
                  </span>
                </label>
              );
            })}
          </div>
        )}

        <div className="flex justify-end mt-4 gap-3">
          <button className="px-4 py-2 border rounded-lg" onClick={onClose}>
            Cancel
          </button>
          <button
            onClick={handleSubmit}
            className="px-5 py-2 bg-cyan-600 text-white rounded-lg"
          >
            Add Items
          </button>
        </div>
      </div>
    </div>
  );
}

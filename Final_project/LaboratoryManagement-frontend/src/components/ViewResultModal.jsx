import React, { useEffect, useState } from "react";
import { fetchResultsByItemId } from "../services/testResultApi";

export default function ViewResultModal({ open, onClose, itemId }) {
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState(null);

  useEffect(() => {
    if (!open || !itemId) return;

    const load = async () => {
      try {
        setLoading(true);
        const res = await fetchResultsByItemId(itemId);
        setResult(res && res.length > 0 ? res[0] : null);
      } catch (err) {
        console.error("Failed to load result", err);
        setResult(null);
      } finally {
        setLoading(false);
      }
    };

    load();
  }, [open, itemId]);

  if (!open) return null;

  return (
    <div className="fixed inset-0 bg-black/20 backdrop-blur-sm flex justify-center items-center z-50 animate-fadeIn">
      <div className="bg-white rounded-2xl shadow-2xl p-7 w-full max-w-lg transform animate-slideUp">
        {/* TITLE */}
        <h2 className="text-2xl font-bold text-gray-800 mb-4">
          🧪 Test Result Detail
        </h2>

        {/* LOADING */}
        {loading ? (
          <div className="py-10 flex justify-center">
            <div className="animate-spin h-10 w-10 border-4 border-cyan-300 border-t-cyan-600 rounded-full"></div>
          </div>
        ) : !result ? (
          <div className="text-center text-gray-500 py-10">
            No result available for this test.
          </div>
        ) : (
          <div className="space-y-3 text-sm text-gray-700">
            {/* Test Name */}
            <div className="flex justify-between">
              <span className="font-semibold">Test Type:</span>
              <span>{result.testTypeName}</span>
            </div>

            {/* Instrument */}
            <div className="flex justify-between">
              <span className="font-semibold">Instrument:</span>
              <span>{result.instrumentName}</span>
            </div>

            {/* Reagent */}
            <div className="flex justify-between">
              <span className="font-semibold">Reagent:</span>
              <span>{result.reagentName}</span>
            </div>

            {/* Value */}
            <div className="flex justify-between">
              <span className="font-semibold">Result Value:</span>
              <span className="font-medium text-cyan-700">
                {result.resultValue} {result.resultUnit}
              </span>
            </div>

            {/* Reference Range */}
            {result.referenceRangeMin !== null && (
              <div className="flex justify-between">
                <span className="font-semibold">Reference Range:</span>
                <span>
                  {result.referenceRangeMin} - {result.referenceRangeMax}
                </span>
              </div>
            )}

            {/* Flag */}
            <div className="flex justify-between">
              <span className="font-semibold">Flag:</span>

              <span
                className={`px-3 py-1 rounded-lg text-xs font-bold
                ${
                  result.flagType === "HIGH"
                    ? "bg-red-100 text-red-700"
                    : result.flagType === "LOW"
                    ? "bg-amber-100 text-amber-700"
                    : "bg-emerald-100 text-emerald-700"
                }`}
              >
                {result.flagType || "NORMAL"}
              </span>
            </div>

            {/* Processed At */}
            <div className="flex justify-between">
              <span className="font-semibold">Processed At:</span>
              <span>
                {result.processedAt
                  ? new Date(result.processedAt).toLocaleString()
                  : "N/A"}
              </span>
            </div>
          </div>
        )}

        {/* BUTTON */}
        <div className="mt-6 flex justify-end">
          <button
            onClick={onClose}
            className="px-5 py-2 bg-cyan-600 hover:bg-teal-600 text-white rounded-lg shadow-md transition"
          >
            Close
          </button>
        </div>
      </div>

      {/* Simple Animations */}
      <style>{`
        @keyframes fadeIn {
          from { opacity: 0 }
          to { opacity: 1 }
        }
        @keyframes slideUp {
          from { transform: translateY(20px); opacity: 0 }
          to { transform: translateY(0); opacity: 1 }
        }
        .animate-fadeIn { animation: fadeIn .2s ease-out }
        .animate-slideUp { animation: slideUp .25s ease-out }
      `}</style>
    </div>
  );
}

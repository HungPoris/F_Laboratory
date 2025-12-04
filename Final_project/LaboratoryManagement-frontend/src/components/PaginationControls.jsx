import React, { useEffect, useRef, useState } from "react";

export default function PaginationControls({
  page,
  size,
  currentPageSize,
  totalElements,
  totalPages,
  onPageChange,
  onSizeChange,
}) {
  const [inputPage, setInputPage] = useState(page + 1);
  const inputRef = useRef(null);

  useEffect(() => setInputPage(page + 1), [page]);

  const maxPages = Math.max(
    1,
    totalPages ?? Math.ceil((totalElements || 0) / size || 1)
  );

  const rangeStart = totalElements === 0 ? 0 : page * size;
  let rangeEnd;
  if (!totalElements) {
    rangeEnd = 0;
  } else if (currentPageSize && currentPageSize > 0) {
    rangeEnd = rangeStart + currentPageSize - 1;
  } else {
    rangeEnd = Math.min(totalElements - 1, (page + 1) * size - 1);
  }
  if (rangeEnd > Math.max(0, totalElements - 1))
    rangeEnd = Math.max(0, totalElements - 1);

  const prevDisabled = page <= 0;
  const nextDisabled = page >= maxPages - 1 || totalElements === 0;

  const goToPageOneBased = (oneBased) => {
    if (!oneBased && oneBased !== 0) return;
    let t = Number(oneBased);
    if (!Number.isFinite(t) || isNaN(t)) return;
    t = Math.max(1, Math.min(t, maxPages));
    const zero = t - 1;
    if (zero !== page) onPageChange(zero);
    else setInputPage(t);
  };

  const onInputKeyDown = (e) => {
    if (e.key === "Enter") {
      goToPageOneBased(inputPage);
      inputRef.current?.blur();
    } else if (e.key === "ArrowUp") {
      goToPageOneBased((inputPage || 1) + 1);
    } else if (e.key === "ArrowDown") {
      goToPageOneBased((inputPage || 1) - 1);
    }
  };

  return (
    <div className="w-full flex items-center justify-center py-4">
      <div className="flex items-center gap-6">
        <button
          className={`w-12 h-12 flex items-center justify-center rounded-full bg-white border border-gray-200 shadow-sm ${
            prevDisabled ? "opacity-40 cursor-not-allowed" : "hover:shadow-lg"
          }`}
          onClick={() => {
            if (!prevDisabled) onPageChange(page - 1);
          }}
          disabled={prevDisabled}
          aria-label="Previous page"
        >
          <span className="text-gray-700 text-lg">←</span>
        </button>

        <div className="px-6 py-3 rounded-full bg-white border border-gray-200 shadow-sm flex items-center gap-4">
          <div className="text-sm text-gray-700">Page</div>

          <input
            ref={inputRef}
            value={inputPage}
            onChange={(e) => {
              const v = e.target.value.replace(/[^\d]/g, "");
              setInputPage(v === "" ? "" : Number(v));
            }}
            onKeyDown={onInputKeyDown}
            onBlur={() => goToPageOneBased(inputPage)}
            className="w-14 text-center rounded-md border border-gray-300 outline-none bg-white text-gray-900 px-2 py-1 focus:ring-2 focus:ring-teal-200"
            aria-label="Page number"
          />

          <div className="text-sm text-gray-700">/ {maxPages}</div>
        </div>

        <button
          className={`w-12 h-12 flex items-center justify-center rounded-full bg-white border border-gray-200 shadow-sm ${
            nextDisabled ? "opacity-40 cursor-not-allowed" : "hover:shadow-lg"
          }`}
          onClick={() => {
            if (!nextDisabled) onPageChange(page + 1);
          }}
          disabled={nextDisabled}
          aria-label="Next page"
        >
          <span className="text-gray-700 text-lg">→</span>
        </button>
      </div>

      <div className="ml-4 flex items-center gap-2">
        <span className="text-sm text-gray-700">Size:</span>
        <select
          value={size}
          onChange={(e) => {
            const newSize = Number(e.target.value);
            onSizeChange(newSize);
          }}
          className="bg-white border border-gray-300 rounded px-3 py-1 text-sm text-gray-700 focus:outline-none focus:ring-2 focus:ring-teal-200"
        >
          <option value={10}>10</option>
          <option value={20}>20</option>
          <option value={50}>50</option>
          <option value={100}>100</option>
        </select>
      </div>
    </div>
  );
}

import React from "react";

export default function Placeholder({ name }) {
  return (
    <div className="p-6">
      <h1 className="text-2xl mb-2">Placeholder</h1>
      <div>
        Đây là trang Placeholder cho: {name || "unknown"}. Bạn cần tạo component
        thực tế trong src/pages để thay thế.
      </div>
    </div>
  );
}

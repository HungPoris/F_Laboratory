import React from "react";

export default function UserHome() {
  return (
    <div className="p-6">
      <h1 className="text-2xl mb-2">USER Home</h1>
      <div>Đây là USER Home (landing-style). screen_code = SCR_USER_HOME</div>
      <nav className="mt-4">
        <a href="/home/results" className="mr-4">
          Xem kết quả xét nghiệm
        </a>
        <a href="/home/profile">Cập nhật thông tin</a>
      </nav>
    </div>
  );
}

import React from "react";
import Sidebar from "../components/layout/Sidebar";
import Topbar from "../components/layout/Topbar";
import adminMenu from "../config/menus/adminMenu";

export default function AdminLayout({ children }) {
  return (
    <div className="min-h-screen flex bg-gray-50">
      <Sidebar menu={adminMenu} />
      <div className="flex-1 flex flex-col">
        <Topbar />
        <main className="flex-1">{children}</main>
      </div>
    </div>
  );
}

import React from "react";
import { useAuth } from "../lib/auth";
import { useLocation } from "react-router-dom";
import Sidebar from "../components/layout/Sidebar";
import Topbar from "../components/layout/Topbar";
import adminMenu from "../config/menus/adminMenu";
import labTechMenu from "../config/menus/labTechMenu";
import labManagerMenu from "../config/menus/labManagerMenu";

export default function RoleAwareLayout({ children }) {
  const { user } = useAuth() || {};
  const location = useLocation();
  const roles = user?.roles || [];

  // Xác định menu dựa trên role
  const getMenuByRole = () => {
    if (roles.includes("ADMIN")) return adminMenu;
    if (roles.includes("LAB_MANAGER")) return labManagerMenu;
    if (roles.includes("LAB_TECH")) return labTechMenu;
    return labTechMenu; // Default fallback
  };

  const menu = getMenuByRole();
  const hideGlobalSidebar = location.pathname.startsWith("/profile");

  return (
    <div className="min-h-screen flex bg-gray-50">
      {!hideGlobalSidebar && <Sidebar menu={menu} />}
      <div className="flex-1 flex flex-col">
        <Topbar />
        <main className="flex-1">{children}</main>
      </div>
    </div>
  );
}

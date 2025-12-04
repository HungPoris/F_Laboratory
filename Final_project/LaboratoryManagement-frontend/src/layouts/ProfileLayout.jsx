import React, { useEffect, useState } from "react";
import { NavLink, Outlet, useLocation, useNavigate } from "react-router-dom";
import {
  User,
  Lock,
  ChevronRight,
  Eye,
  KeyRound,
  LogOut,
  ChevronLeft,
} from "lucide-react";

export default function ProfileLayout() {
  const location = useLocation();
  const navigate = useNavigate();
  const [collapsed, setCollapsed] = useState(false);
  const [openProfile, setOpenProfile] = useState(false);
  const [openSecurity, setOpenSecurity] = useState(false);

  useEffect(() => {
    const p = location.pathname;
    setOpenProfile(p === "/profile" || p.startsWith("/profile/update"));
    setOpenSecurity(
      p === "/profile/security" || p.startsWith("/profile/security")
    );
  }, [location.pathname]);

  const toggleSidebar = () => {
    setCollapsed(!collapsed);
  };

  const toggleProfile = () => {
    setOpenProfile(!openProfile);
    if (!collapsed && !openProfile) {
      navigate("/profile");
    }
  };

  const toggleSecurity = () => {
    setOpenSecurity(!openSecurity);
    if (!collapsed && !openSecurity) {
      navigate("/profile/security/change-password");
    }
  };

  // Exit chỉ quay về trang trước trong history
  const handleExit = () => {
    navigate(-1);
  };

  return (
    <>
      <style>{`
        @keyframes fadeIn {
          from { opacity: 0; transform: translateY(-10px); }
          to { opacity: 1; transform: translateY(0); }
        }
        .animate-fadeIn { animation: fadeIn 0.3s ease-out; }
      `}</style>

      <div className="flex h-screen bg-gray-50">
        <aside
          className={`bg-white border-r border-gray-200 transition-all duration-300 flex flex-col ${
            collapsed ? "w-20" : "w-72"
          }`}
        >
          <div className="p-4 border-b border-gray-200 flex items-center justify-between">
            {!collapsed ? (
              <>
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-lg bg-gradient-to-br from-emerald-500 to-sky-600 flex items-center justify-center text-white font-bold text-lg">
                    FL
                  </div>
                  <div>
                    <h2 className="font-semibold text-gray-800">
                      F-Laboratory
                    </h2>
                    <p className="text-xs text-gray-500">Profile Panel</p>
                  </div>
                </div>
                <button
                  onClick={toggleSidebar}
                  className="p-2 hover:bg-gray-100 rounded-lg transition-colors"
                >
                  <ChevronLeft className="w-5 h-5 text-gray-600" />
                </button>
              </>
            ) : (
              <div className="w-full flex justify-center">
                <button
                  onClick={toggleSidebar}
                  className="w-10 h-10 rounded-lg bg-gradient-to-br from-emerald-500 to-sky-600 flex items-center justify-center text-white font-bold text-lg hover:opacity-90 transition-opacity"
                >
                  FL
                </button>
              </div>
            )}
          </div>

          <nav className="flex-1 p-4 overflow-y-auto">
            <div className={`mb-4 ${collapsed ? "text-center" : ""}`}>
              {!collapsed ? (
                <p className="text-xs font-semibold text-gray-500 px-2">
                  Account
                </p>
              ) : (
                <div className="w-8 h-0.5 bg-gray-300 mx-auto rounded"></div>
              )}
            </div>

            {!collapsed && (
              <div className="px-2 py-2 text-sm font-medium text-gray-700 mb-3">
                Account Management
              </div>
            )}

            <div className="mb-2">
              <button
                onClick={toggleProfile}
                className={`w-full px-3 py-2.5 rounded-lg text-sm font-medium flex items-center transition-all ${
                  openProfile
                    ? "bg-emerald-50 text-emerald-700"
                    : "hover:bg-gray-50 text-gray-700"
                } ${collapsed ? "justify-center" : "justify-between"}`}
                title={collapsed ? "My Profile" : ""}
              >
                <div className="flex items-center gap-3">
                  <User className="w-5 h-5 flex-shrink-0" />
                  {!collapsed && <span>My Profile</span>}
                </div>
                {!collapsed && (
                  <ChevronRight
                    className={`w-4 h-4 transition-transform flex-shrink-0 ${
                      openProfile ? "rotate-90" : ""
                    }`}
                  />
                )}
              </button>

              {openProfile && !collapsed && (
                <div className="mt-1 ml-4 space-y-1 animate-fadeIn">
                  <NavLink
                    to="/profile"
                    end
                    className={({ isActive }) =>
                      `flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-all ${
                        isActive
                          ? "bg-emerald-100 text-emerald-700 font-medium"
                          : "text-gray-600 hover:bg-gray-50"
                      }`
                    }
                  >
                    <Eye className="w-4 h-4" />
                    <span>View Information</span>
                  </NavLink>
                  <NavLink
                    to="/profile/update"
                    className={({ isActive }) =>
                      `flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-all ${
                        isActive
                          ? "bg-emerald-100 text-emerald-700 font-medium"
                          : "text-gray-600 hover:bg-gray-50"
                      }`
                    }
                  >
                    <User className="w-4 h-4" />
                    <span>Update Profile</span>
                  </NavLink>
                </div>
              )}
            </div>

            <div className="mb-2">
              <button
                onClick={toggleSecurity}
                className={`w-full px-3 py-2.5 rounded-lg text-sm font-medium flex items-center transition-all ${
                  openSecurity
                    ? "bg-emerald-50 text-emerald-700"
                    : "hover:bg-gray-50 text-gray-700"
                } ${collapsed ? "justify-center" : "justify-between"}`}
                title={collapsed ? "Password & Security" : ""}
              >
                <div className="flex items-center gap-3">
                  <Lock className="w-5 h-5 flex-shrink-0" />
                  {!collapsed && <span>Password & Security</span>}
                </div>
                {!collapsed && (
                  <ChevronRight
                    className={`w-4 h-4 transition-transform flex-shrink-0 ${
                      openSecurity ? "rotate-90" : ""
                    }`}
                  />
                )}
              </button>

              {openSecurity && !collapsed && (
                <div className="mt-1 ml-4 space-y-1 animate-fadeIn">
                  <NavLink
                    to="/profile/security/change-password"
                    className={({ isActive }) =>
                      `flex items-center gap-3 px-3 py-2 rounded-lg text-sm transition-all ${
                        isActive
                          ? "bg-emerald-100 text-emerald-700 font-medium"
                          : "text-gray-600 hover:bg-gray-50"
                      }`
                    }
                  >
                    <KeyRound className="w-4 h-4" />
                    <span>Change Password</span>
                  </NavLink>
                  {/* "Forgot Password" removed */}
                </div>
              )}
            </div>
          </nav>

          <div className="p-4 border-t border-gray-200">
            <button
              onClick={handleExit}
              className={`w-full px-3 py-2.5 rounded-lg text-sm font-medium flex items-center gap-3 text-red-600 hover:bg-red-50 transition-all ${
                collapsed ? "justify-center" : ""
              }`}
              title={collapsed ? "Exit" : ""}
            >
              <LogOut className="w-5 h-5 flex-shrink-0" />
              {!collapsed && <span>Exit</span>}
            </button>
          </div>
        </aside>

        <main className="flex-1 overflow-y-auto bg-gray-50">
          <div className="p-8">
            <div className="bg-white rounded-2xl shadow-sm border border-gray-200 p-6">
              <Outlet />
            </div>
          </div>
        </main>
      </div>
    </>
  );
}

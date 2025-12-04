import React, { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Bell } from "lucide-react";
import Swal from "sweetalert2";
import { useAuth } from "../../lib/auth";

export default function Topbar({ showNotificationsIf }) {
  const navigate = useNavigate();
  const { user, logout } = useAuth() || {};
  const [open, setOpen] = useState(false);
  const anchorRef = useRef(null);
  const menuRef = useRef(null);
  const hoverTimer = useRef(null);

  useEffect(() => {
    function onDocClick(e) {
      if (!open) return;
      if (
        anchorRef.current &&
        !anchorRef.current.contains(e.target) &&
        menuRef.current &&
        !menuRef.current.contains(e.target)
      ) {
        setOpen(false);
      }
    }
    function onEsc(e) {
      if (e.key === "Escape") setOpen(false);
    }
    document.addEventListener("click", onDocClick);
    document.addEventListener("keydown", onEsc);
    return () => {
      document.removeEventListener("click", onDocClick);
      document.removeEventListener("keydown", onEsc);
    };
  }, [open]);

  const openMenu = () => {
    clearTimeout(hoverTimer.current);
    setOpen(true);
  };
  const closeMenu = () => {
    hoverTimer.current = setTimeout(() => setOpen(false), 120);
  };
  const instantClose = () => setOpen(false);

  const handleLogout = async () => {
    const result = await Swal.fire({
      title: "Confirm logout",
      text: "Are you sure you want to log out?",
      icon: "warning",
      showCancelButton: true,
      confirmButtonColor: "#dc2626",
      cancelButtonColor: "#6b7280",
      confirmButtonText: "Logout",
      cancelButtonText: "Cancel",
    });

    if (!result.isConfirmed) return;

    // logout() sẽ tự động redirect, không cần navigate thêm
    logout();
  };

  function handleAccount() {
    instantClose();
    navigate("/profile");
  }

  const initials = (user?.fullName || user?.username || "U")
    .split(" ")
    .map((s) => s[0])
    .join("")
    .toUpperCase()
    .slice(0, 2);

  // Get role from roles array and format it
  const getFormattedRole = () => {
    if (!user?.roles || !Array.isArray(user.roles) || user.roles.length === 0) {
      return "User";
    }
    const role = user.roles[0];
    return role.charAt(0).toUpperCase() + role.slice(1).toLowerCase();
  };

  const showNotifications =
    typeof showNotificationsIf === "function"
      ? showNotificationsIf(user)
      : false;

  return (
    <header className="bg-white/70 backdrop-blur border-b border-gray-200 sticky top-0 z-50">
      <div className="px-6 py-4 flex items-center justify-between">
        <div className="flex items-center gap-6">
          <h1 className="text-2xl font-bold bg-gradient-to-r from-teal-500 to-emerald-500 bg-clip-text text-transparent">
            Laboratory Management
          </h1>
        </div>

        <div className="flex items-center gap-3 relative">
          {showNotifications && (
            <button className="relative p-2.5 rounded-xl hover:bg-gray-50">
              <Bell className="w-5 h-5 text-gray-600" />
              <span className="absolute top-2 right-2 w-2 h-2 bg-red-500 rounded-full animate-pulse"></span>
            </button>
          )}

          {showNotifications && <div className="h-8 w-px bg-gray-200"></div>}

          <div
            ref={anchorRef}
            className="flex items-center gap-3 px-3 py-2 rounded-xl hover:bg-gray-50 cursor-pointer transition-colors"
            onMouseEnter={openMenu}
            onMouseLeave={closeMenu}
            onClick={() => setOpen((v) => !v)}
            aria-haspopup="menu"
            aria-expanded={open}
          >
            <div className="w-9 h-9 rounded-xl bg-gradient-to-br from-teal-400 via-teal-500 to-emerald-500 flex items-center justify-center text-white font-semibold text-sm">
              {initials}
            </div>
            <div className="hidden md:block">
              <div className="text-sm font-semibold text-gray-800">
                {user?.fullName || user?.username || "User"}
              </div>
              <div className="text-xs text-gray-500">@{getFormattedRole()}</div>
            </div>
            <svg
              width="20"
              height="20"
              viewBox="0 0 24 24"
              className="text-gray-600"
            >
              <path
                d="M8.292 9.707a1 1 0 0 1 1.416-1.414L12 10.585l2.292-2.292a1 1 0 1 1 1.416 1.414l-3 3a1 1 0 0 1-1.416 0l-3-3Z"
                fill="currentColor"
              />
            </svg>
          </div>

          {open && (
            <div
              ref={menuRef}
              onMouseEnter={openMenu}
              onMouseLeave={closeMenu}
              className="absolute top-16 right-0 w-56 rounded-2xl shadow-lg bg-white/35 backdrop-blur-md p-1 animate-in fade-in zoom-in-95"
              role="menu"
            >
              <button
                onClick={handleAccount}
                className="w-full text-left px-3 py-2 rounded-xl text-sm hover:bg-white/50"
                role="menuitem"
              >
                Profile
              </button>
              <div className="my-1 h-px bg-gray-200/50" />
              <button
                onClick={handleLogout}
                className="w-full text-left px-3 py-2 rounded-xl text-sm text-red-600 hover:bg-red-50/70"
                role="menuitem"
              >
                Logout
              </button>
            </div>
          )}
        </div>
      </div>
    </header>
  );
}

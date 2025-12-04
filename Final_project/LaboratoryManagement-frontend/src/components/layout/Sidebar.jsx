import React, { useState } from "react";
import { NavLink, useLocation } from "react-router-dom";
import { ChevronLeft } from "lucide-react";

export default function Sidebar({
  menu = [],
  collapsed: collapsedProp,
  onToggle,
}) {
  const [collapsedLocal, setCollapsedLocal] = useState(false);
  const location = useLocation();
  const collapsed =
    typeof collapsedProp === "boolean" ? collapsedProp : collapsedLocal;
  const toggle = onToggle || (() => setCollapsedLocal((s) => !s));

  const isActive = (itemPath) => {
    const currentPath = location.pathname;

    if (itemPath === "/patients") {
      return (
        currentPath === "/patients" ||
        (currentPath.startsWith("/patients/") &&
          !currentPath.includes("/all-medical-records"))
      );
    }

    return currentPath === itemPath || currentPath.startsWith(itemPath + "/");
  };

  return (
    <aside
      className={`bg-white flex flex-col transition-all duration-300 ${
        collapsed ? "w-20" : "w-72"
      }`}
    >
      <div className="p-6 flex items-center justify-between">
        {!collapsed ? (
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-teal-500 to-emerald-500 flex items-center justify-center shadow-lg">
              <span className="text-white font-bold text-lg">FL</span>
            </div>
            <div>
              <div className="font-bold text-gray-800 text-lg">
                F-Laboratory
              </div>
              <div className="text-xs text-gray-500">Panel</div>
            </div>
          </div>
        ) : (
          <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-teal-500 to-emerald-500 flex items-center justify-center shadow-lg mx-auto">
            <span className="text-white font-bold text-lg">FL</span>
          </div>
        )}
        <button
          onClick={toggle}
          className="p-2 rounded-lg hover:bg-gray-100 transition-colors"
        >
          <ChevronLeft
            className={`w-5 h-5 text-gray-600 transition-transform duration-300 ${
              collapsed ? "rotate-180" : ""
            }`}
          />
        </button>
      </div>

      <nav className="flex-1 p-4 space-y-2">
        {menu.map((item) => {
          if (item.children && item.children.length > 0) {
            return (
              <div key={item.label} className="mb-2">
                {!collapsed && (
                  <div className="px-3 py-1 text-xs font-semibold text-gray-500">
                    {item.label}
                  </div>
                )}
                {item.children.map((c) => {
                  const active = isActive(c.to);
                  return (
                    <NavLink
                      key={c.to}
                      to={c.to}
                      className={`flex items-center gap-3 px-4 py-3 rounded-xl ${
                        active
                          ? "bg-teal-500 text-white"
                          : "text-gray-600 hover:bg-gray-50"
                      }`}
                    >
                      {c.Icon ? (
                        <c.Icon className="w-5 h-5" />
                      ) : (
                        <div className="w-5" />
                      )}
                      {!collapsed && <span>{c.label}</span>}
                    </NavLink>
                  );
                })}
              </div>
            );
          }

          const active = isActive(item.to);
          return (
            <NavLink
              key={item.to}
              to={item.to}
              className={`flex items-center gap-3 px-4 py-3 rounded-xl ${
                active
                  ? "bg-teal-500 text-white"
                  : "text-gray-600 hover:bg-gray-50"
              }`}
            >
              {item.Icon ? (
                <item.Icon className="w-5 h-5" />
              ) : (
                <div className="w-5" />
              )}
              {!collapsed && <span>{item.label}</span>}
            </NavLink>
          );
        })}
      </nav>

      <div className="p-6">
        {!collapsed && (
          <div className="text-xs text-gray-500 text-center">
            © 2025 F-Laboratory
            <div className="mt-1 text-gray-400">Version 1.0</div>
          </div>
        )}
      </div>
    </aside>
  );
}

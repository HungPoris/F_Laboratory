import React, { useEffect, useMemo, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import {
  fetchRoles,
  deleteRole,
  fetchPrivileges,
} from "../../services/adminApi";
import http from "../../lib/api";
import PaginationControls from "../../components/PaginationControls";
import {
  Edit3,
  Trash2,
  Plus,
  Search,
  X,
  CheckCircle2,
  AlertCircle,
  Info,
  Shield,
  ShieldCheck,
  ShieldOff,
  Eye,
  Filter as FilterIcon,
} from "lucide-react";
import { useTranslation } from "react-i18next";
import { useDebounce } from "../../hooks/useDebounce";

const apiCreateRole = async ({
  code,
  name,
  description = "",
  active = true,
  system = false,
  privilegeIds = [],
}) => {
  const trimmedCode = (code || "").trim();
  const trimmedName = (name || "").trim();
  if (!trimmedCode || !trimmedName) {
    throw new Error("Code and name are required");
  }
  const body = {
    code: trimmedCode,
    name: trimmedName,
    description: description || "",
    active,
    system,
    privilegeIds: privilegeIds || [],
  };
  const res = await http.post("/api/v1/admin/roles", body);
  return res.data;
};

const apiUpdateRole = async (
  id,
  { name, description, active, system, privilegeIds } = {}
) => {
  const body = {};
  if (name !== undefined) {
    const trimmedName = (name || "").trim();
    if (trimmedName === "") {
      throw new Error("Name cannot be empty");
    }
    body.name = trimmedName;
  }
  if (description !== undefined) body.description = description ?? "";
  if (active !== undefined) body.active = active;
  if (system !== undefined) body.system = system;
  if (privilegeIds !== undefined) body.privilegeIds = privilegeIds || [];
  const res = await http.put(`/api/v1/admin/roles/${id}`, body);
  return res.data;
};

const getErrorMessage = (error, t) => {
  const errorCode =
    error?.response?.data?.code || error?.code || "UNKNOWN_ERROR";
  return t(`errors.${errorCode}`, { defaultValue: t("errors.UNKNOWN_ERROR") });
};

function Toast({ message, type = "success", onClose }) {
  useEffect(() => {
    const timer = setTimeout(onClose, 4000);
    return () => clearTimeout(timer);
  }, [onClose]);
  const icons = {
    success: <CheckCircle2 className="w-5 h-5" />,
    error: <AlertCircle className="w-5 h-5" />,
    info: <Info className="w-5 h-5" />,
  };
  const styles = {
    success: "from-emerald-500 to-teal-500 shadow-emerald-500/30",
    error: "from-red-500 to-pink-500 shadow-red-500/30",
    info: "from-blue-500 to-indigo-500 shadow-blue-500/30",
  };
  return (
    <div className="fixed top-6 right-6 z-50 animate-slideIn font-sans">
      <div
        className={`bg-gradient-to-r ${styles[type]} text-white px-6 py-4 rounded-2xl shadow-2xl flex items-center gap-3 min-w-[320px]`}
      >
        {icons[type]}
        <span className="flex-1 font-medium">{message}</span>
        <button
          onClick={onClose}
          className="hover:bg-white/20 p-1 rounded-lg transition-colors"
        >
          <X className="w-4 h-4" />
        </button>
      </div>
    </div>
  );
}

function SweetAlert({ title, text, type = "warning", onConfirm, onCancel }) {
  const icons = {
    warning: <AlertCircle className="w-16 h-16 text-orange-500" />,
    danger: <Trash2 className="w-16 h-16 text-red-500" />,
    question: <Info className="w-16 h-16 text-blue-500" />,
  };
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm animate-fadeIn font-sans">
      <div className="bg-white rounded-3xl shadow-2xl p-8 max-w-md w-full mx-4 animate-scaleIn">
        <div className="flex flex-col items-center text-center gap-4">
          {icons[type]}
          <h3 className="text-2xl font-bold text-gray-900">{title}</h3>
          <p className="text-gray-600">{text}</p>
          <div className="flex gap-3 mt-4 w-full">
            <button
              onClick={onCancel}
              className="flex-1 px-6 py-3 rounded-xl border-2 border-gray-200 hover:bg-gray-50 font-semibold text-gray-700 transition-all duration-200"
            >
              Cancel
            </button>
            <button
              onClick={onConfirm}
              className="flex-1 px-6 py-3 rounded-xl bg-gradient-to-r from-red-500 to-pink-500 hover:from-red-600 hover:to-pink-600 text-white font-semibold shadow-lg shadow-red-500/30 hover:shadow-red-500/50 transition-all duration-200"
            >
              Confirm
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function RoleIcon({ roleName = "" }) {
  const colors = [
    "from-blue-400 to-blue-600",
    "from-purple-400 to-purple-600",
    "from-pink-400 to-pink-600",
    "from-teal-400 to-teal-600",
    "from-yellow-400 to-yellow-600",
    "from-red-400 to-red-600",
  ];
  const colorIndex = roleName ? roleName.charCodeAt(0) % colors.length : 0;
  return (
    <div
      className={`w-11 h-11 rounded-xl bg-gradient-to-br ${colors[colorIndex]} flex items-center justify-center text-white shadow-lg`}
    >
      <Shield className="w-6 h-6" />
    </div>
  );
}

function StatusBadge({ isActive }) {
  if (isActive) {
    return (
      <div className="inline-flex items-center gap-2 font-sans">
        <span className="relative flex h-3 w-3">
          <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
          <span className="relative inline-flex rounded-full h-3 w-3 bg-emerald-500"></span>
        </span>
        <span className="text-sm font-medium text-gray-700">Active</span>
      </div>
    );
  }
  return (
    <div className="inline-flex items-center gap-2 font-sans">
      <span className="relative flex h-3 w-3">
        <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-gray-400 opacity-75"></span>
        <span className="relative inline-flex rounded-full h-3 w-3 bg-gray-500"></span>
      </span>
      <span className="text-sm font-medium text-gray-700">Inactive</span>
    </div>
  );
}

function Loading({ size = 40 }) {
  return (
    <div className="flex items-center justify-center font-sans py-12">
      <div className="shapes-5" style={{ width: size, height: size }} />
    </div>
  );
}

function Badge({ children }) {
  return (
    <span className="px-2.5 py-1 rounded-xl text-xs font-medium bg-teal-50 text-teal-600 border border-teal-200">
      {children}
    </span>
  );
}

function useOnClickOutside(ref, handler) {
  useEffect(() => {
    function listener(e) {
      if (!ref.current || ref.current.contains(e.target)) return;
      handler(e);
    }
    document.addEventListener("mousedown", listener);
    document.addEventListener("touchstart", listener);
    return () => {
      document.removeEventListener("mousedown", listener);
      document.removeEventListener("touchstart", listener);
    };
  }, [ref, handler]);
}

function RoleFormModal({ open, mode, initialData, onClose, onSubmit }) {
  // eslint-disable-next-line no-unused-vars
  const { t } = useTranslation();
  const [roleCode, setRoleCode] = useState(initialData?.code || "");
  const [roleName, setRoleName] = useState(initialData?.name || "");
  const [roleDesc, setRoleDesc] = useState(initialData?.description || "");
  const [isSystemRole, setIsSystemRole] = useState(
    initialData?.systemRole || initialData?.isSystemRole || false
  );
  const [privs, setPrivs] = useState([]);
  const [qPriv, setQPriv] = useState("");
  const [openDropdown, setOpenDropdown] = useState(false);
  const [selectedPrivIds, setSelectedPrivIds] = useState(
    new Set(initialData?.privilegeIds || [])
  );
  const [submitting, setSubmitting] = useState(false);
  const dropdownRef = useRef(null);
  useOnClickOutside(dropdownRef, () => setOpenDropdown(false));

  useEffect(() => {
    if (!open) return;
    setRoleCode(initialData?.code || "");
    setRoleName(initialData?.name || "");
    setRoleDesc(initialData?.description || "");
    setIsSystemRole(
      initialData?.systemRole || initialData?.isSystemRole || false
    );
    setSelectedPrivIds(new Set(initialData?.privilegeIds || []));
    setQPriv("");
    setOpenDropdown(false);
    fetchPrivileges()
      .then((list) => {
        setPrivs(list || []);
        if (
          initialData?.privilegeCodes &&
          Array.isArray(initialData.privilegeCodes)
        ) {
          const codeSet = new Set(initialData.privilegeCodes.map((c) => c));
          const matchedIds = (list || [])
            .filter(
              (p) =>
                (p.code && codeSet.has(p.code)) ||
                (p.name && codeSet.has(p.name))
            )
            .map((p) => p.id)
            .filter(Boolean);
          setSelectedPrivIds(new Set(matchedIds));
        } else if (
          initialData?.privileges &&
          Array.isArray(initialData.privileges)
        ) {
          const codeSet = new Set(initialData.privileges.map((c) => c));
          const matchedIds = (list || [])
            .filter(
              (p) =>
                (p.code && codeSet.has(p.code)) ||
                (p.name && codeSet.has(p.name))
            )
            .map((p) => p.id)
            .filter(Boolean);
          setSelectedPrivIds(new Set(matchedIds));
        } else if (
          initialData?.privilegeIds &&
          Array.isArray(initialData.privilegeIds)
        ) {
          setSelectedPrivIds(new Set(initialData?.privilegeIds));
        } else {
          setSelectedPrivIds(new Set());
        }
      })
      .catch(() => {
        setPrivs([]);
        setSelectedPrivIds(new Set());
      });
  }, [open, initialData]);

  const filteredPrivs = useMemo(() => {
    if (!qPriv) return privs;
    const s = qPriv.trim().toLowerCase();
    return privs.filter(
      (p) =>
        (p.code || "").toLowerCase().includes(s) ||
        (p.name || "").toLowerCase().includes(s) ||
        (p.description || "").toLowerCase().includes(s) ||
        (p.category || "").toLowerCase().includes(s)
    );
  }, [qPriv, privs]);

  const allIdsFiltered = useMemo(
    () => filteredPrivs.map((p) => p.id).filter(Boolean),
    [filteredPrivs]
  );
  const allCheckedInFilter =
    allIdsFiltered.length > 0 &&
    allIdsFiltered.every((id) => selectedPrivIds.has(id));
  const checkedCount = selectedPrivIds.size;

  function toggleAllFiltered() {
    const next = new Set(selectedPrivIds);
    if (allCheckedInFilter) {
      allIdsFiltered.forEach((id) => next.delete(id));
    } else {
      allIdsFiltered.forEach((id) => next.add(id));
    }
    setSelectedPrivIds(next);
  }

  function toggleOnePriv(id) {
    const next = new Set(selectedPrivIds);
    if (next.has(id)) next.delete(id);
    else next.add(id);
    setSelectedPrivIds(next);
  }

  async function handleSubmit(e) {
    e.preventDefault();
    const finalCode =
      mode === "create"
        ? (roleCode || "").trim()
        : (initialData?.code || "").trim();
    const finalName = (roleName || initialData?.name || "").trim();
    const finalDesc = (
      roleDesc !== undefined && roleDesc !== null && roleDesc !== ""
        ? roleDesc
        : initialData?.description || ""
    ).toString();
    const finalSystem =
      typeof isSystemRole === "boolean"
        ? isSystemRole
        : !!initialData?.systemRole || !!initialData?.isSystemRole;

    if (mode === "create" && (!finalCode || !finalName)) return;
    if (mode === "edit" && !finalName) return;

    setSubmitting(true);
    try {
      const selectedIds = Array.from(selectedPrivIds);
      await onSubmit({
        code: finalCode,
        name: finalName,
        description: finalDesc,
        system: finalSystem,
        privilegeIds: selectedIds,
      });
      onClose();
    } finally {
      setSubmitting(false);
    }
  }

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/50 backdrop-blur-sm animate-fadeIn font-sans">
      <div className="bg-gradient-to-br from-gray-50 to-white w-full max-w-3xl mx-4 rounded-3xl shadow-2xl border border-gray-200 flex flex-col max-h-[90vh]">
        <div className="p-6 bg-gradient-to-r from-teal-50 to-emerald-50 rounded-t-3xl border-b border-gray-200 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-11 h-11 rounded-2xl bg-gradient-to-br from-teal-500 to-emerald-500 flex items-center justify-center shadow-lg shadow-teal-500/30">
              <Shield className="w-6 h-6 text-white" />
            </div>
            <div>
              <div className="text-2xl font-bold text-gray-900">
                {mode === "create" ? "Create New Role" : "Edit Role"}
              </div>
              <div className="text-gray-500 text-sm">
                Enter role information and assign privileges
              </div>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-2 rounded-xl hover:bg-white transition"
          >
            <X className="w-5 h-5 text-gray-500" />
          </button>
        </div>

        <form
          onSubmit={handleSubmit}
          className="flex-1 overflow-y-auto p-6 space-y-5 overscroll-contain"
        >
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <div className="flex items-center justify-between mb-2">
                <label className="text-sm font-semibold text-gray-700">
                  Role Code
                </label>
                <Badge>Required</Badge>
              </div>
              <input
                value={roleCode}
                onChange={(e) =>
                  setRoleCode(e.target.value.toUpperCase().replace(/\s+/g, "_"))
                }
                placeholder="e.g., ADMIN, MANAGER"
                className={`w-full px-4 py-3 rounded-2xl border-2 border-gray-200 focus:outline-none focus:ring-2 focus:ring-teal-500/20 focus:border-teal-500 font-mono bg-white ${
                  mode === "edit"
                    ? "bg-gray-50 text-gray-600 cursor-not-allowed"
                    : ""
                }`}
                disabled={mode === "edit"}
              />
            </div>
            <div>
              <div className="flex items-center justify-between mb-2">
                <label className="text-sm font-semibold text-gray-700">
                  Role Name
                </label>
                <Badge>Required</Badge>
              </div>
              <input
                value={roleName}
                onChange={(e) => setRoleName(e.target.value)}
                placeholder="e.g., System Administrator"
                className="w-full px-4 py-3 rounded-2xl border-2 border-gray-200 focus:outline-none focus:ring-2 focus:ring-teal-500/20 focus:border-teal-500 bg-white"
              />
            </div>
          </div>

          <div>
            <div className="flex items-center justify-between mb-2">
              <label className="text-sm font-semibold text-gray-700">
                Role Description
              </label>
              <span className="text-xs text-gray-400">Max 500 characters</span>
            </div>
            <textarea
              value={roleDesc}
              onChange={(e) => setRoleDesc(e.target.value)}
              rows={3}
              placeholder="Brief description of the role"
              className="w-full px-4 py-3 rounded-2xl border-2 border-gray-200 focus:outline-none focus:ring-2 focus:ring-teal-500/20 focus:border-teal-500 bg-white"
              maxLength={500}
            />
          </div>

          <div className="relative" ref={dropdownRef}>
            <div className="flex items-center justify-between mb-2">
              <label className="text-sm font-semibold text-gray-700">
                Assign Privileges
              </label>
              <div className="text-xs text-gray-500">
                {checkedCount} selected
              </div>
            </div>
            <button
              type="button"
              onClick={() => setOpenDropdown((v) => !v)}
              className="w-full px-4 py-3 rounded-2xl border-2 border-gray-200 bg-white flex items-center justify-between hover:border-gray-300"
            >
              <span className="text-gray-600">
                {checkedCount > 0
                  ? `${checkedCount} privileges selected`
                  : "Select privileges..."}
              </span>
              {openDropdown ? (
                <X className="w-4 h-4 text-gray-500" />
              ) : (
                <Search className="w-4 h-4 text-gray-500" />
              )}
            </button>

            {openDropdown && (
              <div className="absolute z-50 mt-2 w-full rounded-2xl border border-gray-200 bg-white shadow-xl">
                <div className="p-3 border-b border-gray-100 sticky top-0 bg-white rounded-t-2xl">
                  <div className="relative">
                    <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
                    <input
                      value={qPriv}
                      onChange={(e) => setQPriv(e.target.value)}
                      placeholder="Search by code, name, description, category..."
                      className="w-full pl-9 pr-3 py-2.5 rounded-xl border-2 border-gray-200 focus:outline-none focus:ring-2 focus:ring-teal-500/20 focus:border-teal-500"
                    />
                  </div>
                  <div className="flex items-center gap-3 mt-3">
                    <button
                      type="button"
                      onClick={toggleAllFiltered}
                      className="px-3 py-2 rounded-xl border-2 border-gray-200 hover:border-gray-300 hover:bg-gray-50 text-sm font-medium"
                    >
                      {allCheckedInFilter ? "Deselect All" : "Select All"}
                    </button>
                    <div className="text-xs text-gray-500">
                      {filteredPrivs.length} privileges shown
                    </div>
                  </div>
                </div>

                <div className="max-h-72 overflow-auto">
                  {filteredPrivs.map((p) => {
                    const id = p.id;
                    const checked = selectedPrivIds.has(id);
                    return (
                      <label
                        key={id}
                        className="flex items-center gap-3 px-4 py-2.5 hover:bg-teal-50/50 cursor-pointer"
                      >
                        <input
                          type="checkbox"
                          checked={checked}
                          onChange={() => toggleOnePriv(id)}
                          className="w-4 h-4 rounded border-2 border-gray-300 text-teal-600 focus:ring-teal-500"
                        />
                        <div className="flex-1">
                          <div className="text-sm font-semibold text-gray-800">
                            {p.name || p.description || p.code}
                          </div>
                          {p.description && p.description !== p.name && (
                            <div className="text-xs text-gray-500">
                              {p.description}
                            </div>
                          )}
                        </div>
                        {p.category && (
                          <span className="px-2.5 py-1 rounded-xl text-xs font-medium bg-teal-50 text-teal-600 border border-teal-200">
                            {p.category}
                          </span>
                        )}
                      </label>
                    );
                  })}

                  {filteredPrivs.length === 0 && (
                    <div className="px-4 py-6 text-center text-sm text-gray-500">
                      No matching privileges found
                    </div>
                  )}
                </div>
              </div>
            )}
          </div>

          <div className="sticky bottom-0 pt-2 bg-gradient-to-br from-gray-50 to-white rounded-b-3xl">
            <div className="flex items-center justify-end gap-3 border-t border-gray-100 pt-4">
              <button
                type="button"
                onClick={onClose}
                className="px-5 py-3 rounded-2xl border-2 border-gray-200 hover:bg-gray-50 font-semibold text-gray-700"
                disabled={submitting}
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={
                  submitting ||
                  (mode === "create" &&
                    (!(roleCode || "").trim() || !(roleName || "").trim()))
                }
                className={`px-6 py-3 rounded-2xl text-white font-semibold shadow-lg shadow-teal-500/30 bg-gradient-to-r from-teal-500 to-emerald-500 hover:from-teal-600 hover:to-emerald-600 ${
                  submitting ? "opacity-70 cursor-not-allowed" : ""
                }`}
              >
                {submitting
                  ? "Saving..."
                  : mode === "create"
                  ? "Create Role"
                  : "Save Changes"}
              </button>
            </div>
          </div>
        </form>
      </div>
    </div>
  );
}

function RoleViewModal({ open, role, onClose }) {
  const [privs, setPrivs] = useState([]);
  const [loading, setLoading] = useState(false);
  useEffect(() => {
    if (!open) return;
    setLoading(true);
    fetchPrivileges()
      .then((list) => setPrivs(list || []))
      .finally(() => setLoading(false));
  }, [open]);
  if (!open || !role) return null;
  const matchByCodes = Array.isArray(role.privilegeCodes)
    ? new Set(role.privilegeCodes)
    : null;
  const matchByIds = Array.isArray(role.privilegeIds)
    ? new Set(role.privilegeIds)
    : null;
  const rolePrivs = privs.filter((p) => {
    if (matchByIds && p.id) return matchByIds.has(p.id);
    if (matchByCodes && (p.code || p.name))
      return matchByCodes.has(p.code) || matchByCodes.has(p.name);
    return false;
  });
  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/50 backdrop-blur-sm animate-fadeIn font-sans">
      <div className="bg-gradient-to-br from-gray-50 to-white w-full max-w-2xl mx-4 rounded-3xl shadow-2xl border border-gray-200 flex flex-col max-h-[85vh]">
        <div className="p-6 bg-gradient-to-r from-teal-50 to-emerald-50 rounded-t-3xl border-b border-gray-200 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-11 h-11 rounded-2xl bg-gradient-to-br from-teal-500 to-emerald-500 flex items-center justify-center shadow-lg shadow-teal-500/30">
              <Eye className="w-6 h-6 text-white" />
            </div>
            <div>
              <div className="text-2xl font-bold text-gray-900">Role Info</div>
              <div className="text-gray-500 text-sm">
                Details and assigned privileges
              </div>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-2 rounded-xl hover:bg-white transition"
          >
            <X className="w-5 h-5 text-gray-500" />
          </button>
        </div>

        <div className="p-6 overflow-y-auto space-y-5">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="bg-white rounded-2xl border border-gray-200 p-4">
              <div className="text-xs uppercase text-gray-500 mb-1">Code</div>
              <div className="font-mono font-semibold text-gray-900">
                {role.code || role.id}
              </div>
            </div>
            <div className="bg-white rounded-2xl border border-gray-200 p-4">
              <div className="text-xs uppercase text-gray-500 mb-1">Name</div>
              <div className="font-semibold text-gray-900">{role.name}</div>
            </div>
            <div className="bg-white rounded-2xl border border-gray-200 p-4">
              <div className="text-xs uppercase text-gray-500 mb-1">Status</div>
              <StatusBadge isActive={role.active !== false} />
            </div>
            <div className="bg-white rounded-2xl border border-gray-200 p-4">
              <div className="text-xs uppercase text-gray-500 mb-1">System</div>
              {role.system ? (
                <span className="px-2.5 py-1 rounded-xl text-xs font-medium bg-purple-50 text-purple-600 border border-purple-200">
                  System Role
                </span>
              ) : (
                <span className="px-2.5 py-1 rounded-xl text-xs font-medium bg-gray-50 text-gray-600 border border-gray-200">
                  Normal Role
                </span>
              )}
            </div>
          </div>

          {role.description && (
            <div className="bg-white rounded-2xl border border-gray-200 p-4">
              <div className="text-xs uppercase text-gray-500 mb-2">
                Description
              </div>
              <div className="text-gray-800">{role.description}</div>
            </div>
          )}

          <div className="bg-white rounded-2xl border border-gray-200 p-4">
            <div className="flex items-center justify-between mb-3">
              <div className="text-xs uppercase text-gray-500">Privileges</div>
              <div className="text-xs text-gray-400">
                {loading ? "Loading..." : `${rolePrivs.length} items`}
              </div>
            </div>
            <div className="flex flex-wrap gap-2">
              {loading && (
                <span className="px-3 py-1.5 rounded-xl text-xs bg-gray-100 text-gray-500 border border-gray-200">
                  Fetching privileges...
                </span>
              )}
              {!loading && rolePrivs.length === 0 && (
                <span className="px-3 py-1.5 rounded-xl text-xs bg-gray-100 text-gray-500 border border-gray-200">
                  No privileges assigned
                </span>
              )}
              {!loading &&
                rolePrivs.map((p) => (
                  <span
                    key={p.id || p.code || p.name}
                    className="px-3 py-1.5 rounded-xl text-xs font-medium bg-teal-50 text-teal-700 border border-teal-200"
                    title={p.description || p.name || p.code}
                  >
                    {/* 🔹 Ưu tiên hiển thị code trong chip */}
                    {p.code ?? p.name}
                  </span>
                ))}
            </div>
          </div>
        </div>

        <div className="p-4 border-t border-gray-100 rounded-b-3xl bg-gradient-to-br from-gray-50 to-white flex justify-end">
          <button
            onClick={onClose}
            className="px-5 py-3 rounded-2xl border-2 border-gray-200 hover:bg-gray-50 font-semibold text-gray-700"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
}

export default function RolesList() {
  const { t } = useTranslation();
  // eslint-disable-next-line no-unused-vars
  const navigate = useNavigate();
  const [allRoles, setAllRoles] = useState([]);
  const [displayRoles, setDisplayRoles] = useState([]);
  const [loading, setLoading] = useState(false);
  const [q, setQ] = useState("");
  const debouncedQ = useDebounce(q, 500);
  const [toast, setToast] = useState(null);
  const [alert, setAlert] = useState(null);
  const [openCreate, setOpenCreate] = useState(false);
  const [openEdit, setOpenEdit] = useState(false);
  const [editingRole, setEditingRole] = useState(null);
  const [openView, setOpenView] = useState(false);
  const [viewingRole, setViewingRole] = useState(null);
  const [filterOpen, setFilterOpen] = useState(false);
  const [filters, setFilters] = useState({
    code: "",
    name: "",
    status: "any",
  });

  const [page, setPage] = useState(0);
  const [size, setSize] = useState(10);
  const [totalElements, setTotalElements] = useState(0);
  const [totalPages, setTotalPages] = useState(1);

  async function load(
    keyword = "",
    currentPage = 0,
    currentSize = 10,
    f = filters
  ) {
    setLoading(true);
    try {
      const baseQ = keyword.trim();
      const codeFilter = (f.code || "").trim();
      const nameFilter = (f.name || "").trim();
      const mergedQParts = [];
      if (baseQ) mergedQParts.push(baseQ);
      if (codeFilter) mergedQParts.push(codeFilter);
      if (nameFilter) mergedQParts.push(nameFilter);
      const params = {
        page: currentPage,
        size: currentSize,
      };
      const mergedQ = mergedQParts.join(" ").trim();
      if (mergedQ) params.q = mergedQ;
      if (f.status && f.status !== "any") params.status = f.status;
      const r = await fetchRoles(params);
      let items = [];
      let total = 0;
      let pages = 1;
      if (Array.isArray(r)) {
        items = r;
        total = r.length;
        pages = 1;
      } else if (r && Array.isArray(r.content)) {
        items = r.content;
        total = r.totalElements || r.content.length;
        pages = r.totalPages || 1;
      } else {
        items = [];
        total = 0;
        pages = 1;
      }
      setDisplayRoles(items);
      setTotalElements(total);
      setTotalPages(pages || 1);
      if (
        currentPage === 0 &&
        !baseQ &&
        !codeFilter &&
        !nameFilter &&
        (f.status === "any" || !f.status)
      ) {
        setAllRoles(items);
      }
    } catch (err) {
      setToast({ message: getErrorMessage(err, t), type: "error" });
      setDisplayRoles([]);
      setTotalElements(0);
      setTotalPages(1);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load("", 0, size, filters);
  }, []);

  useEffect(() => {
    setPage(0);
  }, [debouncedQ, filters.code, filters.name, filters.status]);

  useEffect(() => {
    load(debouncedQ, page, size, filters);
  }, [page, size, debouncedQ, filters.code, filters.name, filters.status]);

  const showToast = (message, type = "success") => {
    setToast({ message, type });
  };

  const showAlert = (config) => {
    setAlert(config);
  };

  const onDelete = (role) => {
    const id = role.id;
    const name = role.name || "";
    showAlert({
      title: "Confirm Delete",
      text: `Are you sure you want to delete role "${name}"?`,
      type: "danger",
      onConfirm: async () => {
        try {
          await deleteRole(id);
          setAlert(null);
          showToast("Role deleted successfully!", "success");
          load(debouncedQ, page, size, filters);
        } catch (err) {
          setAlert(null);
          showToast(getErrorMessage(err, t), "error");
        }
      },
      onCancel: () => setAlert(null),
    });
  };

  async function submitCreate(values) {
    try {
      const { code, name, description, system, privilegeIds } = values;
      const trimmedCode = (code || "").trim();
      const trimmedName = (name || "").trim();
      if (!trimmedCode || !trimmedName) {
        setToast({
          message: "Code and name are required fields",
          type: "error",
        });
        return;
      }
      const created = await apiCreateRole({
        code: trimmedCode,
        name: trimmedName,
        description: description || "",
        active: true,
        system: !!system,
        privilegeIds: Array.isArray(privilegeIds) ? privilegeIds : [],
      });
      setDisplayRoles((xs) => [created, ...xs]);
      setToast({ message: "Role created successfully!", type: "success" });
      load(debouncedQ, page, size, filters);
    } catch (err) {
      setToast({ message: getErrorMessage(err, t), type: "error" });
    }
  }

  async function submitEdit(values) {
    if (!editingRole) return;
    try {
      const finalName = (values?.name || editingRole.name || "").trim();
      if (!finalName) {
        setToast({ message: "Role name cannot be empty", type: "error" });
        return;
      }
      const payload = {
        name: finalName,
        description:
          values?.description !== undefined
            ? values.description
            : editingRole.description || "",
        active:
          values?.active !== undefined
            ? values.active
            : editingRole.active !== false,
        system:
          values?.system !== undefined ? values.system : editingRole.system,
      };
      if (Array.isArray(values?.privilegeIds)) {
        payload.privilegeIds = values.privilegeIds;
      }
      const updated = await apiUpdateRole(editingRole.id, payload);
      setDisplayRoles((xs) =>
        xs.map((r) => (r.id === editingRole.id ? updated : r))
      );
      setToast({ message: "Role updated successfully!", type: "success" });
      load(debouncedQ, page, size, filters);
    } catch (err) {
      setToast({ message: getErrorMessage(err, t), type: "error" });
    }
  }

  const paginatedItems = displayRoles;

  const finalTotalElements = totalElements;
  const finalTotalPages = totalPages || 1;

  const [colCodeValue, setColCodeValue] = useState(filters.code || "");
  const [colNameValue, setColNameValue] = useState(filters.name || "");
  const [colStatusValue, setColStatusValue] = useState(filters.status || "any");

  useEffect(() => {
    setColCodeValue(filters.code || "");
    setColNameValue(filters.name || "");
    setColStatusValue(filters.status || "any");
  }, [filters]);

  const resetAllFilters = () => {
    setFilters({ code: "", name: "", status: "any" });
    setColCodeValue("");
    setColNameValue("");
    setColStatusValue("any");
    setFilterOpen(false);
  };

  const openFilterModal = () => {
    setFilterOpen(true);
  };

  const closeFilterModal = () => {
    setFilterOpen(false);
  };

  const handlePageChange = (newPage) => {
    setPage(newPage);
  };

  const handleSizeChange = (newSize) => {
    setSize(newSize);
    setPage(0);
  };

  return (
    <div className="p-6 bg-gradient-to-br from-gray-50 via-white to-teal-50/30 min-h-screen font-sans">
      {toast && <Toast {...toast} onClose={() => setToast(null)} />}
      {alert && <SweetAlert {...alert} />}

      <div className="max-w-7xl mx-auto">
        <div className="mb-8">
          <div className="flex items-center gap-4 mb-3">
            <div className="w-12 h-12 rounded-2xl bg-gradient-to-br from-teal-500 to-emerald-500 flex items-center justify-center shadow-lg shadow-teal-500/30">
              <Shield className="w-6 h-6 text-white" />
            </div>
            <div>
              <h1 className="text-4xl font-bold text-gray-900">
                Role Management
              </h1>
              <p className="text-gray-500 mt-1">
                Manage and assign privileges to roles in the system
              </p>
            </div>
          </div>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
          {[
            {
              label: "Total Roles",
              value: finalTotalElements,
              icon: Shield,
              iconColor: "text-teal-600",
            },
            {
              label: "Active",
              value: allRoles.filter((r) => r.active !== false).length,
              icon: ShieldCheck,
              iconColor: "text-emerald-600",
            },
            {
              label: "Inactive",
              value: allRoles.filter((r) => r.active === false).length,
              icon: ShieldOff,
              iconColor: "text-gray-600",
            },
          ].map((stat, i) => {
            const IconComponent = stat.icon;
            return (
              <div
                key={i}
                className="bg-white rounded-2xl p-5 shadow-sm border border-gray-200 hover:shadow-xl transition-all duration-300 hover:-translate-y-1"
              >
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-gray-500 text-sm font-medium">
                      {stat.label}
                    </p>
                    <p className="text-3xl font-bold text-gray-900 mt-1">
                      {stat.value}
                    </p>
                  </div>
                  <div className="w-14 h-14 rounded-2xl bg-gray-50 flex items-center justify-center">
                    <IconComponent className={`w-8 h-8 ${stat.iconColor}`} />
                  </div>
                </div>
              </div>
            );
          })}
        </div>

        <div className="bg-white rounded-3xl shadow-xl border border-gray-200 overflow-hidden">
          <div className="p-6 border-b border-gray-200 bg-gradient-to-r from-gray-50 to-white">
            <div className="flex flex-col sm:flex-row gap-4 items-start sm:items-center justify-between">
              <div className="flex-1 w-full sm:w-auto">
                <div className="relative group">
                  <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-400 group-focus-within:text-teal-500 transition-colors" />
                  <input
                    value={q}
                    onChange={(e) => setQ(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") {
                        e.preventDefault();
                        load(e.target.value, 0, size, filters);
                      }
                    }}
                    placeholder="Search by role name, role code..."
                    className="w-full pl-12 pr-4 py-3.5 border-2 border-gray-200 rounded-2xl focus:outline-none focus:ring-2 focus:ring-teal-500/20 focus:border-teal-500 transition-all bg-white"
                  />
                </div>
              </div>

              <div className="flex gap-3">
                <button
                  onClick={openFilterModal}
                  className="px-5 py-3.5 rounded-2xl border-2 border-gray-200 hover:border-gray-300 hover:bg-gray-50 transition-all duration-200 flex items-center gap-2 text-gray-700 font-medium hover:shadow-lg"
                >
                  <FilterIcon className="w-4 h-4" />
                  <span className="hidden sm:inline">Filter</span>
                </button>

                <button
                  onClick={() => setOpenCreate(true)}
                  className="px-6 py-3.5 rounded-2xl bg-gradient-to-r from-teal-500 to-emerald-500 hover:from-teal-600 hover:to-emerald-600 text-white font-semibold transition-all duration-200 flex items-center gap-2 shadow-lg shadow-teal-500/40 hover:shadow-teal-500/60 hover:-translate-y-0.5"
                >
                  <Plus className="w-5 h-5" />
                  <span>Add Role</span>
                </button>
              </div>
            </div>
          </div>

          {loading ? (
            <div className="py-24">
              <Loading size={50} />
            </div>
          ) : (
            <>
              <div className="overflow-x-auto" style={{ overflow: "visible" }}>
                <table className="w-full">
                  <thead>
                    <tr className="bg-gray-50">
                      <th className="text-left px-6 py-4 text-xs font-bold text-gray-600 uppercase tracking-wider">
                        <div className="flex items-center gap-2">
                          <span>Role Code</span>
                        </div>
                      </th>
                      <th className="text-left px-6 py-4 text-xs font-bold text-gray-600 uppercase tracking-wider">
                        <div className="flex items-center gap-2">
                          <span>Role Name</span>
                        </div>
                      </th>
                      <th className="text-center px-6 py-4 text-xs font-bold text-gray-600 uppercase tracking-wider">
                        <div className="flex items-center justify-center gap-2">
                          <span>Status</span>
                        </div>
                      </th>
                      <th className="text-center px-6 py-4 text-xs font-bold text-gray-600 uppercase tracking-wider">
                        Actions
                      </th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-100">
                    {paginatedItems.map((role, index) => {
                      const isActive = role.active !== false;
                      return (
                        <tr
                          key={role.id}
                          className="hover:bg-gradient-to-r hover:from-teal-50/30 hover:to-transparent transition-all duration-200 group"
                          style={{
                            animation: `slideUp 0.4s ease-out ${
                              index * 0.05
                            }s both`,
                          }}
                        >
                          <td className="px-6 py-5">
                            <div className="flex items-center gap-4">
                              <RoleIcon roleName={role.name || ""} />
                              <div>
                                <div className="font-mono text-sm font-semibold text-gray-900 group-hover:text-teal-600 transition-colors">
                                  {role.code || role.id}
                                </div>
                              </div>
                            </div>
                          </td>

                          <td className="px-6 py-5">
                            <div className="font-semibold text-gray-900">
                              {role.name}
                            </div>
                            {role.description && (
                              <div className="text-sm text-gray-500 mt-1">
                                {role.description}
                              </div>
                            )}
                          </td>

                          <td className="px-6 py-5">
                            <div className="flex justify-center">
                              <StatusBadge isActive={isActive} />
                            </div>
                          </td>

                          <td className="px-6 py-5">
                            <div className="flex items-center justify-center gap-1">
                              <button
                                onClick={() => {
                                  setViewingRole(role);
                                  setOpenView(true);
                                }}
                                className="p-2.5 rounded-xl hover:bg-blue-50 transition-all duration-200 group/btn hover:scale-110"
                                title="View"
                              >
                                <Eye className="w-4 h-4 text-gray-400 group-hover/btn:text-blue-600 transition-colors" />
                              </button>

                              <button
                                onClick={() => {
                                  setEditingRole(role);
                                  setOpenEdit(true);
                                }}
                                className="p-2.5 rounded-xl hover:bg-green-50 transition-all duration-200 group/btn hover:scale-110"
                                title="Edit"
                              >
                                <Edit3 className="w-4 h-4 text-gray-400 group-hover/btn:text-green-600 transition-colors" />
                              </button>

                              <button
                                onClick={() => onDelete(role)}
                                className="p-2.5 rounded-xl hover:bg-red-50 transition-all duration-200 group/btn hover:scale-110"
                                title="Delete"
                              >
                                <Trash2 className="w-4 h-4 text-gray-400 group-hover/btn:text-red-600 transition-colors" />
                              </button>
                            </div>
                          </td>
                        </tr>
                      );
                    })}

                    {paginatedItems.length === 0 && (
                      <tr>
                        <td colSpan={4} className="px-6 py-20 text-center">
                          <div className="flex flex-col items-center gap-4">
                            <div className="w-20 h-20 rounded-full bg-gradient-to-br from-gray-100 to-gray-200 flex items-center justify-center">
                              <Shield className="w-10 h-10 text-gray-400" />
                            </div>
                            <div>
                              <div className="text-gray-700 font-semibold text-lg">
                                No roles found
                              </div>
                              <div className="text-sm text-gray-500 mt-1">
                                Try changing your search keywords or filters
                              </div>
                            </div>
                          </div>
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>

              <PaginationControls
                page={page}
                size={size}
                currentPageSize={paginatedItems.length}
                totalElements={finalTotalElements}
                totalPages={finalTotalPages}
                onPageChange={handlePageChange}
                onSizeChange={handleSizeChange}
              />
            </>
          )}
        </div>
      </div>

      <RoleFormModal
        open={openCreate}
        mode="create"
        initialData={null}
        onClose={() => setOpenCreate(false)}
        onSubmit={submitCreate}
      />

      <RoleFormModal
        open={openEdit}
        mode="edit"
        initialData={
          editingRole
            ? {
                id: editingRole.id,
                code: editingRole.code,
                name: editingRole.name,
                description: editingRole.description,
                systemRole: editingRole.system === true,
                privilegeCodes: editingRole.privilegeCodes || [],
                privilegeIds: [],
              }
            : null
        }
        onClose={() => {
          setOpenEdit(false);
          setEditingRole(null);
        }}
        onSubmit={submitEdit}
      />

      <RoleViewModal
        open={openView}
        role={viewingRole}
        onClose={() => {
          setOpenView(false);
          setViewingRole(null);
        }}
      />

      {filterOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40">
          <div className="bg-white rounded-2xl shadow-xl p-6 w-full max-w-lg">
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-3">
                <FilterIcon className="w-6 h-6 text-teal-600" />
                <div className="text-lg font-semibold">Filter roles</div>
              </div>
              <button
                onClick={closeFilterModal}
                className="p-2 rounded-md hover:bg-gray-100"
              >
                <X className="w-5 h-5 text-gray-600" />
              </button>
            </div>

            <div className="space-y-4">
              <div>
                <label className="text-sm text-gray-600 block mb-1">
                  Role Code
                </label>
                <input
                  value={colCodeValue}
                  onChange={(e) => setColCodeValue(e.target.value)}
                  placeholder="Filter by code"
                  className="w-full px-3 py-2 rounded-md border border-gray-200"
                />
              </div>

              <div>
                <label className="text-sm text-gray-600 block mb-1">
                  Role Name
                </label>
                <input
                  value={colNameValue}
                  onChange={(e) => setColNameValue(e.target.value)}
                  placeholder="Filter by name"
                  className="w-full px-3 py-2 rounded-md border border-gray-200"
                />
              </div>

              <div>
                <label className="text-sm text-gray-600 block mb-1">
                  Status
                </label>
                <select
                  value={colStatusValue}
                  onChange={(e) => setColStatusValue(e.target.value)}
                  className="w-full px-3 py-2 rounded-md border border-gray-200"
                >
                  <option value="any">Any</option>
                  <option value="active">Active</option>
                  <option value="inactive">Inactive</option>
                </select>
              </div>
            </div>

            <div className="flex justify-end gap-3 mt-6">
              <button
                onClick={resetAllFilters}
                className="px-4 py-2 rounded-md border border-gray-200"
              >
                Reset
              </button>
              <button
                onClick={() => {
                  setFilters({
                    code: colCodeValue,
                    name: colNameValue,
                    status: colStatusValue,
                  });
                  setFilterOpen(false);
                }}
                className="px-4 py-2 rounded-md bg-teal-600 text-white"
              >
                Apply
              </button>
            </div>
          </div>
        </div>
      )}

      <style>{`
        @keyframes slideUp { from { opacity: 0; transform: translateY(20px); } to { opacity: 1; transform: translateY(0); } }
        @keyframes slideIn { from { opacity: 0; transform: translateX(100px); } to { opacity: 1; transform: translateX(0); } }
        @keyframes fadeIn { from { opacity: 0; } to { opacity: 1; } }
        @keyframes scaleIn { from { opacity: 0; transform: scale(0.9); } to { opacity: 1; transform: scale(1); } }
        .shapes-5 {
          width: 40px;
          aspect-ratio: 1;
          --c: no-repeat linear-gradient(#14b8a6 0 0);
          background:
            var(--c) 0%   100%,
            var(--c) 50%  100%,
            var(--c) 100% 100%;
          animation: sh5 1s infinite linear;
        }
        @keyframes sh5 {
          0%   {background-size: 20% 100%,20% 100%,20% 100%}
          33%  {background-size: 20% 10% ,20% 100%,20% 100%}
          50%  {background-size: 20% 100%,20% 10% ,20% 100%}
          66%  {background-size: 20% 100%,20% 100%,20% 10% }
          100% {background-size: 20% 100%,20% 100%,20% 100%}
        }
      `}</style>
    </div>
  );
}

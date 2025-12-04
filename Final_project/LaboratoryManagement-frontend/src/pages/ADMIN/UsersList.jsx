import React, { useEffect, useState, useMemo } from "react";
import { useNavigate } from "react-router-dom";
import { useTranslation } from "react-i18next";
import { useDebounce } from "../../hooks/useDebounce";
import {
  fetchUsers,
  deleteUser,
  lockUser,
  unlockUser,
  banUser,
  unbanUser,
  fetchRoles,
} from "../../services/adminApi";
import {
  Edit3,
  Trash2,
  Lock,
  Unlock,
  Plus,
  Search,
  Filter,
  UserX,
  X,
  Ban,
  CheckCircle2,
  AlertCircle,
  Info,
  Users,
  UserCheck,
  ShieldAlert,
  Eye,
  Mail,
  Phone,
  Calendar,
  CreditCard,
  MapPin,
  User,
  Shield,
} from "lucide-react";
import Loading from "../../components/Loading";
import PaginationControls from "../../components/PaginationControls";

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
    <div className="fixed top-6 right-6 z-50 animate-slideIn">
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
  const { t } = useTranslation();

  const icons = {
    warning: <AlertCircle className="w-16 h-16 text-orange-500" />,
    danger: <Ban className="w-16 h-16 text-red-500" />,
    question: <Info className="w-16 h-16 text-blue-500" />,
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm animate-fadeIn">
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
              {t("common.cancel", "Cancel")}
            </button>
            <button
              onClick={onConfirm}
              className="flex-1 px-6 py-3 rounded-xl bg-gradient-to-r from-red-500 to-pink-500 hover:from-red-600 hover:to-pink-600 text-white font-semibold shadow-lg shadow-red-500/30 hover:shadow-red-500/50 transition-all duration-200"
            >
              {t("common.confirm", "Confirm")}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function Avatar({ name = "" }) {
  const initials = (name || "U").slice(0, 2).toUpperCase();
  const colors = [
    "from-blue-400 to-blue-600",
    "from-purple-400 to-purple-600",
    "from-pink-400 to-pink-600",
    "from-green-400 to-green-600",
    "from-yellow-400 to-yellow-600",
    "from-red-400 to-red-600",
  ];
  const colorIndex = name?.charCodeAt?.(0)
    ? name.charCodeAt(0) % colors.length
    : 0;

  return (
    <div
      className={`w-11 h-11 rounded-xl bg-gradient-to-br ${colors[colorIndex]} flex items-center justify-center text-white font-bold shadow-lg`}
    >
      {initials}
    </div>
  );
}

function StatusBadge({ isActive, isLocked }) {
  const { t } = useTranslation();

  if (!isActive) {
    return (
      <div className="inline-flex items-center gap-2">
        <div className="w-6 h-6 rounded-full bg-red-50 flex items-center justify-center">
          <X className="w-4 h-4 text-red-500" />
        </div>
        <span className="text-sm font-medium text-gray-700">
          {t("admin.status_disabled", "Disabled")}
        </span>
      </div>
    );
  }

  if (isLocked) {
    return (
      <div className="inline-flex items-center gap-2">
        <div className="w-6 h-6 rounded-full bg-orange-50 flex items-center justify-center">
          <Lock className="w-4 h-4 text-orange-500" />
        </div>
        <span className="text-sm font-medium text-gray-700">
          {t("admin.status_locked", "Locked")}
        </span>
      </div>
    );
  }

  return (
    <div className="inline-flex items-center gap-2">
      <span className="relative flex h-3 w-3">
        <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
        <span className="relative inline-flex rounded-full h-3 w-3 bg-emerald-500"></span>
      </span>
      <span className="text-sm font-medium text-gray-700">
        {t("admin.status_active", "Active")}
      </span>
    </div>
  );
}

function getErrorMessage(error, t) {
  const errorCode =
    error?.response?.data?.code ||
    error?.response?.data?.error ||
    error?.response?.data?.errorCode;

  if (errorCode) {
    const errorKey = `errors.${errorCode}`;
    const translated = t(errorKey, errorCode);
    if (translated && translated !== errorKey) {
      return translated;
    }
    return errorCode;
  }

  if (error?.response?.data?.message) {
    const message = error.response.data.message;
    const errorKey = `errors.${message}`;
    const translated = t(errorKey, message);
    if (translated && translated !== errorKey) {
      return translated;
    }
    return message;
  }

  if (error?.message === "Network Error" || !error?.response) {
    return t(
      "errors.NETWORK_ERROR",
      "A network error occurred. Please check your internet connection and try again."
    );
  }

  const status = error?.response?.status;
  if (status === 401) {
    return t("errors.UNAUTHORIZED", "Not authenticated.");
  }
  if (status === 403) {
    return t("errors.FORBIDDEN", "You do not have access.");
  }
  if (status === 404) {
    return t("errors.USER_NOT_FOUND", "The user was not found.");
  }
  if (status === 500) {
    return t("errors.GENERAL_ERROR", "An error occurred. Please try again.");
  }

  return t(
    "errors.UNKNOWN_ERROR",
    "An unknown error occurred. Please try again."
  );
}

function FilterModal({
  open,
  onClose,
  onApply,
  availableRoles,
  initial,
  roleCodeToName,
}) {
  const { t } = useTranslation();
  const [status, setStatus] = useState(initial?.status || "all");
  const [role, setRole] = useState(initial?.role || "");

  useEffect(() => {
    if (open) {
      setStatus(initial?.status || "all");
      setRole(initial?.role || "");
    }
  }, [open, initial]);

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 animate-fadeIn p-4">
      <div className="bg-white rounded-3xl shadow-2xl w-full max-w-lg p-6 animate-scaleIn">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold">
            {t("admin.filter", "Filter")}
          </h3>
          <button
            onClick={onClose}
            className="p-2 rounded-lg hover:bg-gray-100"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        <div className="space-y-4">
          <div>
            <label className="block text-sm text-gray-600 mb-1">
              {t("admin.status", "Status")}
            </label>
            <select
              value={status}
              onChange={(e) => setStatus(e.target.value)}
              className="w-full px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-teal-200"
            >
              <option value="all">{t("admin.all", "All")}</option>
              <option value="active">{t("admin.active", "Active")}</option>
              <option value="locked">{t("admin.locked", "Locked")}</option>
              <option value="disabled">
                {t("admin.disabled", "Disabled")}
              </option>
            </select>
          </div>

          <div>
            <label className="block text-sm text-gray-600 mb-1">
              {t("admin.role", "Role")}
            </label>
            <select
              value={role}
              onChange={(e) => setRole(e.target.value)}
              className="w-full px-4 py-2 border rounded-lg focus:outline-none focus:ring-2 focus:ring-teal-200"
            >
              <option value="">{t("admin.any_role", "Any role")}</option>
              {availableRoles.map((r) => {
                const roleCode = typeof r === "string" ? r : r.code;
                const roleName =
                  typeof r === "string"
                    ? roleCodeToName?.[r] || r
                    : r.name || r.code;
                return (
                  <option key={roleCode} value={roleCode}>
                    {roleName}
                  </option>
                );
              })}
            </select>
          </div>
        </div>

        <div className="mt-6 flex justify-end gap-3">
          <button
            onClick={() => {
              setStatus("all");
              setRole("");
            }}
            className="px-4 py-2 rounded-lg border hover:bg-gray-50"
          >
            {t("common.reset", "Reset")}
          </button>
          <button
            onClick={() => onApply({ status, role })}
            className="px-4 py-2 rounded-lg bg-gradient-to-r from-teal-500 to-emerald-500 text-white"
          >
            {t("common.apply", "Apply")}
          </button>
        </div>
      </div>
    </div>
  );
}

function UserViewModal({ user, onClose, roleCodeToName }) {
  const { t } = useTranslation();
  if (!user) return null;

  const fullname = user.fullName || user.full_name || user.username || "";
  const rolesArr = Array.isArray(user.roles)
    ? user.roles
    : Array.from(user.roles || []);

  const formatDate = (dateStr) => {
    if (!dateStr) return "N/A";
    try {
      const date = new Date(dateStr);
      return date.toLocaleDateString("en-GB");
    } catch {
      return dateStr;
    }
  };

  const formatGender = (gender) => {
    if (!gender) return "N/A";
    const g = String(gender).toUpperCase();
    if (g === "MALE") return "Male";
    if (g === "FEMALE") return "Female";
    if (g === "OTHER") return "Other";
    return gender;
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm animate-fadeIn">
      <div className="bg-white rounded-3xl shadow-2xl p-8 max-w-3xl w-full mx-4 animate-scaleIn max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between mb-6">
          <h3 className="text-2xl font-bold text-gray-900">
            {t("admin.user_details", "User Details")}
          </h3>
          <button
            onClick={onClose}
            className="p-2 rounded-lg hover:bg-gray-100 transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        <div className="flex items-center gap-4 mb-6 pb-6 border-b border-gray-200">
          <Avatar name={fullname} />
          <div>
            <div className="text-xl font-semibold text-gray-900">
              {fullname}
            </div>
            <div className="text-sm text-gray-500">@{user.username}</div>
          </div>
        </div>

        <div className="space-y-6">
          <div>
            <h4 className="text-lg font-semibold text-gray-900 mb-4 flex items-center gap-2">
              <User className="w-5 h-5 text-emerald-500" />
              Basic Information
            </h4>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="bg-gray-50 rounded-xl p-4">
                <label className="block text-sm font-medium text-gray-600 mb-1 flex items-center gap-2">
                  <Mail className="w-4 h-4" />
                  Email
                </label>
                <div className="text-gray-900 font-medium">
                  {user.email || "N/A"}
                </div>
              </div>

              <div className="bg-gray-50 rounded-xl p-4">
                <label className="block text-sm font-medium text-gray-600 mb-1 flex items-center gap-2">
                  <Phone className="w-4 h-4" />
                  Phone Number
                </label>
                <div className="text-gray-900 font-medium">
                  {user.phoneNumber || user.phone_number || "N/A"}
                </div>
              </div>

              <div className="bg-gray-50 rounded-xl p-4">
                <label className="block text-sm font-medium text-gray-600 mb-1 flex items-center gap-2">
                  <Calendar className="w-4 h-4" />
                  Date of Birth
                </label>
                <div className="text-gray-900 font-medium">
                  {formatDate(user.dateOfBirth || user.date_of_birth)}
                </div>
              </div>

              <div className="bg-gray-50 rounded-xl p-4">
                <label className="block text-sm font-medium text-gray-600 mb-1 flex items-center gap-2">
                  <UserCheck className="w-4 h-4" />
                  Gender
                </label>
                <div className="text-gray-900 font-medium">
                  {formatGender(user.gender)}
                </div>
              </div>

              <div className="bg-gray-50 rounded-xl p-4 md:col-span-2">
                <label className="block text-sm font-medium text-gray-600 mb-1 flex items-center gap-2">
                  <CreditCard className="w-4 h-4" />
                  Citizen ID / Passport
                </label>
                <div className="text-gray-900 font-medium">
                  {user.identityNumber || user.identity_number || "N/A"}
                </div>
              </div>
            </div>
          </div>

          <div>
            <h4 className="text-lg font-semibold text-gray-900 mb-4 flex items-center gap-2">
              <MapPin className="w-5 h-5 text-emerald-500" />
              Address
            </h4>
            <div className="bg-gray-50 rounded-xl p-4">
              <div className="text-gray-900">{user.address || "N/A"}</div>
            </div>
          </div>

          <div>
            <h4 className="text-lg font-semibold text-gray-900 mb-4 flex items-center gap-2">
              <Shield className="w-5 h-5 text-emerald-500" />
              {t("admin.role_column", "Roles")}
            </h4>
            <div className="flex gap-2 flex-wrap">
              {rolesArr
                .map((role) => {
                  const roleCode =
                    (typeof role === "string" ? role : role?.code || role) ||
                    "";
                  const cleanCode = roleCode.replace(/^ROLE_/, "");
                  return cleanCode;
                })
                .filter((r) => r)
                .map((roleCode, i) => {
                  const roleName = roleCodeToName?.[roleCode] || roleCode;
                  return (
                    <span
                      key={i}
                      className="px-3 py-1.5 rounded-lg bg-gradient-to-r from-purple-50 to-pink-50 text-purple-700 text-sm font-semibold border border-purple-200"
                    >
                      {roleName}
                    </span>
                  );
                })}
              {rolesArr.length === 0 && (
                <span className="text-sm text-gray-500">No roles assigned</span>
              )}
            </div>
          </div>

          <div>
            <h4 className="text-lg font-semibold text-gray-900 mb-4 flex items-center gap-2">
              <Info className="w-5 h-5 text-emerald-500" />
              {t("admin.status_column", "Status")}
            </h4>
            <div className="bg-gray-50 rounded-xl p-4">
              <StatusBadge isActive={user.isActive} isLocked={user.isLocked} />
            </div>
          </div>
        </div>

        <div className="mt-8 flex justify-end gap-3 pt-6 border-t border-gray-200">
          <button
            onClick={onClose}
            className="px-6 py-2.5 rounded-xl bg-gray-100 hover:bg-gray-200 text-gray-700 font-medium transition-colors"
          >
            {t("common.close", "Close")}
          </button>
        </div>
      </div>
    </div>
  );
}

export default function UsersList() {
  const navigate = useNavigate();
  const { t } = useTranslation();
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(false);
  const [q, setQ] = useState("");
  const debouncedQ = useDebounce(q, 500);
  const [toast, setToast] = useState(null);
  const [alert, setAlert] = useState(null);
  const [busyId, setBusyId] = useState(null);
  const [viewUser, setViewUser] = useState(null);

  const [allRoles, setAllRoles] = useState([]);
  // eslint-disable-next-line no-unused-vars
  const [rolesLoading, setRolesLoading] = useState(false);

  const [filterOpen, setFilterOpen] = useState(false);
  const [appliedFilters, setAppliedFilters] = useState({
    status: "all",
    role: "",
  });

  const [page, setPage] = useState(0);
  const [size, setSize] = useState(10);
  const [totalElements, setTotalElements] = useState(0);
  const [totalPages, setTotalPages] = useState(1);

  const showToast = (message, type = "success") => {
    setToast({ message, type });
  };

  const showAlert = (config) => {
    setAlert(config);
  };

  const goEdit = (u) => {
    const id = u.userId || u.id;
    if (!id) return;
    navigate(`/admin/users/${encodeURIComponent(id)}/edit`);
  };

  async function loadRoles() {
    setRolesLoading(true);
    try {
      const response = await fetchRoles({ page: 0, size: 1000 });
      let rolesData = [];
      if (Array.isArray(response)) {
        rolesData = response;
      } else if (response?.data && Array.isArray(response.data)) {
        rolesData = response.data;
      } else if (response?.content && Array.isArray(response.content)) {
        rolesData = response.content;
      } else if (
        response?.data?.content &&
        Array.isArray(response.data.content)
      ) {
        rolesData = response.data.content;
      }
      const normalizedRoles = rolesData.map((role) => ({
        id: role.id || role.roleId,
        code: (role.code || role.roleCode || "").replace(/^ROLE_/, ""),
        name: role.name || role.roleName || role.code || "",
        description: role.description || "",
        active: role.active !== undefined ? role.active : true,
      }));
      setAllRoles(normalizedRoles);
    } catch (err) {
      showToast(getErrorMessage(err, t), "error");
      setAllRoles([]);
    } finally {
      setRolesLoading(false);
    }
  }

  async function loadUsers(
    currentPage = 0,
    currentSize = 10,
    query = "",
    filters = appliedFilters
  ) {
    setLoading(true);
    try {
      const params = {
        page: currentPage,
        size: currentSize,
      };
      if (query && query.trim() !== "") {
        params.q = query.trim();
      }
      if (filters.status && filters.status !== "all") {
        params.status = filters.status;
      }
      if (filters.role) {
        params.role = filters.role;
      }
      const r = await fetchUsers(params);
      let items = [];
      let total = 0;
      let pages = 1;
      if (!r) {
        items = [];
      } else if (Array.isArray(r.content)) {
        items = r.content;
        total = r.totalElements || r.content.length;
        pages = r.totalPages || 1;
      } else if (Array.isArray(r.data?.content)) {
        items = r.data.content;
        total = r.data.totalElements || r.data.content.length;
        pages = r.data.totalPages || 1;
      } else if (Array.isArray(r.data)) {
        items = r.data;
        total = r.data.length;
        pages = 1;
      } else if (Array.isArray(r)) {
        items = r;
        total = r.length;
        pages = 1;
      }
      setUsers(items);
      setTotalElements(total);
      setTotalPages(pages || 1);
    } catch (err) {
      showToast(getErrorMessage(err, t), "error");
      setUsers([]);
      setTotalElements(0);
      setTotalPages(1);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    loadRoles();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    setPage(0);
  }, [debouncedQ, appliedFilters.status, appliedFilters.role]);

  useEffect(() => {
    loadUsers(page, size, debouncedQ, appliedFilters);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page, size, debouncedQ, appliedFilters.status, appliedFilters.role]);

  const roleCodeToName = useMemo(() => {
    const map = {};
    allRoles.forEach((role) => {
      map[role.code] = role.name;
    });
    return map;
  }, [allRoles]);

  const availableRoles = useMemo(() => {
    return allRoles
      .filter((role) => role.active)
      .sort((a, b) => (a.name || a.code).localeCompare(b.name || b.code));
  }, [allRoles]);

  const paginatedUsers = users;

  const onDelete = (user) => {
    const id = user.userId || user.id;
    const fullname = user.fullName || user.full_name || user.username || "";
    showAlert({
      title: t("admin.confirm_delete_title", "Delete user?"),
      text: t("admin.confirm_delete_message", {
        name: fullname,
        defaultValue: `Are you sure you want to delete ${fullname}?`,
      }),
      type: "danger",
      onConfirm: async () => {
        setAlert(null);
        try {
          await deleteUser(id);
          loadUsers(page, size, debouncedQ, appliedFilters);
          showToast(
            t("admin.delete_success", "User deleted successfully!"),
            "success"
          );
        } catch (err) {
          showToast(getErrorMessage(err, t), "error");
        }
      },
      onCancel: () => setAlert(null),
    });
  };

  const onToggleLock = (user) => {
    const id = user.userId || user.id;
    const fullname = user.fullName || user.full_name || user.username || "";
    const isLocked = user.isLocked;
    showAlert({
      title: isLocked
        ? t("admin.confirm_unlock_title", "Unlock user?")
        : t("admin.confirm_lock_title", "Lock user?"),
      text: isLocked
        ? t("admin.confirm_unlock_message", {
            name: fullname,
            defaultValue: `Unlock ${fullname}?`,
          })
        : t("admin.confirm_lock_message", {
            name: fullname,
            defaultValue: `Lock ${fullname}?`,
          }),
      type: "warning",
      onConfirm: async () => {
        setAlert(null);
        try {
          setBusyId(id);
          if (isLocked) {
            await unlockUser(id);
          } else {
            await lockUser(id);
          }
          loadUsers(page, size, debouncedQ, appliedFilters);
          showToast(
            isLocked
              ? t("admin.unlock_success", "Account unlocked successfully!")
              : t("admin.lock_success", "Account locked successfully!"),
            "success"
          );
        } catch (err) {
          showToast(getErrorMessage(err, t), "error");
        } finally {
          setBusyId(null);
        }
      },
      onCancel: () => setAlert(null),
    });
  };

  const onToggleBan = (user) => {
    const id = user.userId || user.id;
    const fullname = user.fullName || user.full_name || user.username || "";
    const isBanned = !user.isActive;
    if (isBanned) {
      showAlert({
        title: t("admin.confirm_activate_title", "Activate user?"),
        text: t("admin.confirm_activate_message", {
          name: fullname,
          defaultValue: `Activate ${fullname}?`,
        }),
        type: "warning",
        onConfirm: async () => {
          setAlert(null);
          try {
            setBusyId(id);
            await unbanUser(id);
            loadUsers(page, size, debouncedQ, appliedFilters);
            showToast(
              t("admin.activate_success", "Account activated successfully!"),
              "success"
            );
          } catch (err) {
            showToast(getErrorMessage(err, t), "error");
          } finally {
            setBusyId(null);
          }
        },
        onCancel: () => setAlert(null),
      });
    } else {
      showAlert({
        title: t("admin.confirm_disable_title", "Disable user?"),
        text: t("admin.confirm_disable_message", {
          name: fullname,
          defaultValue: `Disable ${fullname}?`,
        }),
        type: "danger",
        onConfirm: async () => {
          setAlert(null);
          try {
            setBusyId(id);
            await banUser(id, "Disabled by administrator");
            loadUsers(page, size, debouncedQ, appliedFilters);
            showToast(
              t("admin.disable_success", "Account disabled successfully!"),
              "success"
            );
          } catch (err) {
            showToast(getErrorMessage(err, t), "error");
          } finally {
            setBusyId(null);
          }
        },
        onCancel: () => setAlert(null),
      });
    }
  };

  const handleApplyFilter = (filters) => {
    setAppliedFilters(filters);
    setFilterOpen(false);
  };

  const handleResetFilter = () => {
    setAppliedFilters({ status: "all", role: "" });
    setPage(0);
  };

  const activeFilterCount = [
    appliedFilters.status !== "all" ? 1 : 0,
    appliedFilters.role ? 1 : 0,
  ].reduce((a, b) => a + b, 0);

  return (
    <div className="p-6 bg-gradient-to-br from-gray-50 to-gray-100 min-h-screen">
      {toast && <Toast {...toast} onClose={() => setToast(null)} />}
      {alert && <SweetAlert {...alert} />}
      {viewUser && (
        <UserViewModal
          user={viewUser}
          onClose={() => setViewUser(null)}
          roleCodeToName={roleCodeToName}
        />
      )}

      <FilterModal
        open={filterOpen}
        onClose={() => setFilterOpen(false)}
        onApply={handleApplyFilter}
        availableRoles={availableRoles}
        initial={appliedFilters}
        roleCodeToName={roleCodeToName}
      />

      <div className="max-w-7xl mx-auto">
        <div className="mb-8">
          <div className="flex items-center gap-4 mb-3">
            <div className="w-12 h-12 rounded-2xl bg-gradient-to-br from-teal-500 to-emerald-500 flex items-center justify-center shadow-lg shadow-teal-500/30">
              <UserX className="w-6 h-6 text-white" />
            </div>
            <div>
              <h1 className="text-4xl font-bold text-gray-900">
                {t("admin.user_management", "User Management")}
              </h1>
              <p className="text-gray-500 mt-1">
                {t(
                  "admin.user_management_subtitle",
                  "Manage and monitor all users in the system"
                )}
              </p>
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div className="bg-white rounded-2xl p-6 shadow-lg border border-gray-100">
              <div className="flex items-center justify-between">
                <div>
                  <div className="text-sm text-gray-500 mb-1">
                    {t("admin.total_users", "Total Users")}
                  </div>
                  <div className="text-3xl font-bold text-gray-900">
                    {totalElements}
                  </div>
                </div>
                <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-blue-50 to-blue-100 flex items-center justify-center">
                  <Users className="w-6 h-6 text-blue-600" />
                </div>
              </div>
            </div>

            <div className="bg-white rounded-2xl p-6 shadow-lg border border-gray-100">
              <div className="flex items-center justify-between">
                <div>
                  <div className="text-sm text-gray-500 mb-1">
                    {t("admin.active_users", "Active")}
                  </div>
                  <div className="text-3xl font-bold text-gray-900">
                    {users.filter((u) => u.isActive && !u.isLocked).length}
                  </div>
                </div>
                <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-green-50 to-green-100 flex items-center justify-center">
                  <UserCheck className="w-6 h-6 text-green-600" />
                </div>
              </div>
            </div>

            <div className="bg-white rounded-2xl p-6 shadow-lg border border-gray-100">
              <div className="flex items-center justify-between">
                <div>
                  <div className="text-sm text-gray-500 mb-1">
                    {t("admin.locked_disabled", "Locked/Disabled")}
                  </div>
                  <div className="text-3xl font-bold text-gray-900">
                    {users.filter((u) => !u.isActive || u.isLocked).length}
                  </div>
                </div>
                <div className="w-12 h-12 rounded-xl bg-gradient-to-br from-orange-50 to-orange-100 flex items-center justify-center">
                  <ShieldAlert className="w-6 h-6 text-orange-600" />
                </div>
              </div>
            </div>
          </div>
        </div>

        <div className="bg-white rounded-3xl shadow-xl border border-gray-100 overflow-hidden">
          <div className="p-6 border-b border-gray-100">
            <div className="flex flex-col md:flex-row gap-4 items-start md:items-center justify-between">
              <div className="flex-1 w-full md:w-auto">
                <div className="relative">
                  <Search className="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-400" />
                  <input
                    type="text"
                    placeholder={t(
                      "admin.search_users_placeholder",
                      "Search by name, username or email..."
                    )}
                    value={q}
                    onChange={(e) => setQ(e.target.value)}
                    className="w-full pl-12 pr-4 py-3 rounded-2xl border-2 border-gray-200 focus:outline-none focus:ring-2 focus:ring-teal-500/20 focus:border-teal-500 transition-all"
                  />
                </div>
              </div>

              <div className="flex gap-3">
                <button
                  onClick={() => setFilterOpen(true)}
                  className="relative px-6 py-3 rounded-2xl border-2 border-gray-200 hover:border-teal-500 hover:bg-teal-50 transition-all duration-200 flex items-center gap-2 font-semibold text-gray-700 hover:text-teal-600"
                >
                  <Filter className="w-5 h-5" />
                  {t("admin.filter", "Filter")}
                  {activeFilterCount > 0 && (
                    <span className="absolute -top-1 -right-1 w-5 h-5 rounded-full bg-gradient-to-r from-teal-500 to-emerald-500 text-white text-xs flex items-center justify-center font-bold">
                      {activeFilterCount}
                    </span>
                  )}
                </button>

                {activeFilterCount > 0 && (
                  <button
                    onClick={handleResetFilter}
                    className="px-4 py-3 rounded-2xl bg-gray-100 hover:bg-gray-200 transition-all duration-200 flex items-center gap-2 font-semibold text-gray-700"
                  >
                    <X className="w-5 h-5" />
                  </button>
                )}

                <button
                  onClick={() => navigate("/admin/users/create")}
                  className="px-6 py-3 rounded-2xl bg-gradient-to-r from-teal-500 to-emerald-500 hover:from-teal-600 hover:to-emerald-600 text-white font-semibold shadow-lg shadow-teal-500/30 hover:shadow-teal-500/50 transition-all duration-200 flex items-center gap-2"
                >
                  <Plus className="w-5 h-5" />
                  {t("admin.create_user", "Create User")}
                </button>
              </div>
            </div>
          </div>

          {loading ? (
            <div className="py-20">
              <Loading />
            </div>
          ) : (
            <>
              <div className="overflow-x-auto">
                <table className="w-full">
                  <thead>
                    <tr className="bg-gradient-to-r from-gray-50 to-transparent border-b border-gray-100">
                      <th className="px-6 py-4 text-left text-sm font-semibold text-gray-700">
                        {t("admin.name_column", "User")}
                      </th>
                      <th className="px-6 py-4 text-left text-sm font-semibold text-gray-700">
                        {t("admin.email_column", "Email")}
                      </th>
                      <th className="px-6 py-4 text-left text-sm font-semibold text-gray-700">
                        {t("admin.role_column", "Role")}
                      </th>
                      <th className="px-6 py-4 text-center text-sm font-semibold text-gray-700">
                        {t("admin.status_column", "Status")}
                      </th>
                      <th className="px-6 py-4 text-center text-sm font-semibold text-gray-700">
                        {t("admin.actions_column", "Actions")}
                      </th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-100">
                    {paginatedUsers.map((u, index) => {
                      const id = u.userId || u.id;
                      const fullname =
                        u.fullName || u.full_name || u.username || "";
                      const rolesArr = Array.isArray(u.roles)
                        ? u.roles
                        : Array.from(u.roles || []);
                      return (
                        <tr
                          key={id || index}
                          className="hover:bg-gradient-to-r hover:from-gray-50 hover:to-transparent transition-all duration-200 group"
                          style={{
                            animation: `slideUp 0.4s ease-out ${
                              index * 0.05
                            }s both`,
                          }}
                        >
                          <td className="px-6 py-5">
                            <div className="flex items-center gap-4">
                              <Avatar name={fullname} />
                              <div>
                                <div className="font-semibold text-gray-900 group-hover:text-teal-600 transition-colors">
                                  {fullname}
                                </div>
                                <div className="text-sm text-gray-500">
                                  @{u.username}
                                </div>
                              </div>
                            </div>
                          </td>
                          <td className="px-6 py-5">
                            <div className="text-sm text-gray-700">
                              {u.email}
                            </div>
                          </td>
                          <td className="px-6 py-5">
                            <div className="flex gap-1 flex-wrap">
                              {rolesArr
                                .map((role) => {
                                  const roleCode =
                                    (typeof role === "string"
                                      ? role
                                      : role?.code || role) || "";
                                  const cleanCode = roleCode.replace(
                                    /^ROLE_/,
                                    ""
                                  );
                                  return cleanCode;
                                })
                                .filter((r) => r)
                                .map((roleCode, i) => {
                                  const roleName =
                                    roleCodeToName[roleCode] || roleCode;
                                  return (
                                    <span
                                      key={i}
                                      className="px-3 py-1 rounded-lg bg-gradient-to-r from-purple-50 to-pink-50 text-purple-700 text-xs font-semibold border border-purple-200"
                                    >
                                      {roleName}
                                    </span>
                                  );
                                })}
                              {rolesArr.length === 0 && (
                                <span className="text-sm text-gray-400">
                                  {t("admin.no_role", "No role assigned")}
                                </span>
                              )}
                            </div>
                          </td>
                          <td className="px-6 py-5">
                            <div className="flex justify-center">
                              <StatusBadge
                                isActive={u.isActive}
                                isLocked={u.isLocked}
                              />
                            </div>
                          </td>
                          <td className="px-6 py-5">
                            <div className="flex items-center justify-center gap-1">
                              <button
                                type="button"
                                onClick={() => setViewUser(u)}
                                className="p-2.5 rounded-xl hover:bg-teal-50 transition-all duration-200 group/btn hover:scale-110"
                                title={t("admin.view_user", "View details")}
                                disabled={busyId === id}
                              >
                                <Eye className="w-4 h-4 text-gray-400 group-hover/btn:text-teal-600 transition-colors" />
                              </button>
                              <button
                                type="button"
                                onClick={() => goEdit(u)}
                                className="p-2.5 rounded-xl hover:bg-blue-50 transition-all duration-200 group/btn hover:scale-110"
                                title={t("admin.edit_user", "Edit")}
                                disabled={busyId === id}
                              >
                                <Edit3 className="w-4 h-4 text-gray-400 group-hover/btn:text-blue-600 transition-colors" />
                              </button>
                              <button
                                onClick={() => onToggleLock(u)}
                                className="p-2.5 rounded-xl hover:bg-orange-50 transition-all duration-200 group/btn hover:scale-110 disabled:opacity-50 disabled:cursor-not-allowed"
                                title={
                                  u.isLocked
                                    ? t("admin.unlock_user", "Unlock")
                                    : t("admin.lock_user", "Lock")
                                }
                                disabled={!u.isActive || busyId === id}
                              >
                                {u.isLocked ? (
                                  <Unlock className="w-4 h-4 text-gray-400 group-hover/btn:text-emerald-600 transition-colors" />
                                ) : (
                                  <Lock className="w-4 h-4 text-gray-400 group-hover/btn:text-orange-600 transition-colors" />
                                )}
                              </button>
                              <button
                                onClick={() => onToggleBan(u)}
                                className={`p-2.5 rounded-xl transition-all duration-200 group/btn hover:scale-110 ${
                                  !u.isActive
                                    ? "hover:bg-green-50"
                                    : "hover:bg-red-50"
                                } disabled:opacity-50 disabled:cursor-not-allowed`}
                                title={
                                  !u.isActive
                                    ? t("admin.activate_user", "Activate")
                                    : t("admin.disable_user", "Disable")
                                }
                                disabled={busyId === id}
                              >
                                <Ban
                                  className={`w-4 h-4 transition-colors ${
                                    !u.isActive
                                      ? "text-green-600 group-hover/btn:text-green-700"
                                      : "text-gray-400 group-hover/btn:text-red-600"
                                  }`}
                                />
                              </button>
                              <button
                                onClick={() => onDelete(u)}
                                className="p-2.5 rounded-xl hover:bg-red-50 transition-all duration-200 group/btn hover:scale-110 disabled:opacity-50 disabled:cursor-not-allowed"
                                title={t("admin.delete_user", "Delete")}
                                disabled={busyId === id}
                              >
                                <Trash2 className="w-4 h-4 text-gray-400 group-hover/btn:text-red-600 transition-colors" />
                              </button>
                            </div>
                          </td>
                        </tr>
                      );
                    })}
                    {paginatedUsers.length === 0 && (
                      <tr>
                        <td colSpan={5} className="px-6 py-20 text-center">
                          <div className="flex flex-col items-center gap-4">
                            <div className="w-20 h-20 rounded-full bg-gradient-to-br from-gray-100 to-gray-200 flex items-center justify-center">
                              <UserX className="w-10 h-10 text-gray-400" />
                            </div>
                            <div>
                              <div className="text-gray-700 font-semibold text-lg">
                                {t("admin.no_users_found", "No users found")}
                              </div>
                              <div className="text-sm text-gray-500 mt-1">
                                {t(
                                  "admin.try_different_keywords",
                                  "Try different search keywords"
                                )}
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
                currentPageSize={paginatedUsers.length}
                totalElements={totalElements}
                totalPages={totalPages}
                onPageChange={(p) => setPage(p)}
                onSizeChange={(s) => {
                  setSize(s);
                  setPage(0);
                }}
              />
            </>
          )}
        </div>
      </div>

      <style>{`
        @keyframes slideUp {
          from { opacity: 0; transform: translateY(20px); }
          to { opacity: 1; transform: translateY(0); }
        }
        @keyframes slideIn {
          from { opacity: 0; transform: translateX(100px); }
          to { opacity: 1; transform: translateX(0); }
        }
        @keyframes fadeIn {
          from { opacity: 0; }
          to { opacity: 1; }
        }
        @keyframes scaleIn {
          from { opacity: 0; transform: scale(0.9); }
          to { opacity: 1; transform: scale(1); }
        }
      `}</style>
    </div>
  );
}

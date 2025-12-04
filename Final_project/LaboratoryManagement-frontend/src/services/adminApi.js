import http from "../lib/api";

function normalizePageParams(p, s) {
  if (p == null && s == null) return {};
  if (p != null && typeof p === "object") {
    const { page, pageNumber, size, pageSize, ...rest } = p;
    const pageValue = Number.isFinite(page)
      ? page
      : Number.isFinite(pageNumber)
      ? pageNumber
      : undefined;
    const sizeValue = Number.isFinite(size)
      ? size
      : Number.isFinite(pageSize)
      ? pageSize
      : undefined;
    return {
      ...rest,
      ...(pageValue !== undefined ? { page: pageValue } : {}),
      ...(sizeValue !== undefined ? { size: sizeValue } : {}),
    };
  }
  const pageValue = Number.isFinite(p) ? p : undefined;
  const sizeValue = Number.isFinite(s) ? s : undefined;
  return {
    ...(pageValue !== undefined ? { page: pageValue } : {}),
    ...(sizeValue !== undefined ? { size: sizeValue } : {}),
  };
}

export const fetchUsers = async (pageOrPageable = 0, size = 20) => {
  const params = normalizePageParams(pageOrPageable, size);
  const response = await http.get("/api/v1/admin/users", { params });
  return response.data;
};

export const fetchUserById = async (userId) => {
  const response = await http.get(`/api/v1/admin/users/${userId}`);
  return response.data;
};

export const createUser = async (userData, options = {}) => {
  const { revealPassword = false } = options;
  const params = {};
  if (revealPassword) {
    params.revealPassword = true;
  }
  const response = await http.post("/api/v1/admin/users", userData, { params });
  return response.data;
};

export const updateUser = async (userId, userData) => {
  const response = await http.put(`/api/v1/admin/users/${userId}`, userData);
  return response.data;
};

export const deleteUser = async (userId) => {
  const response = await http.delete(`/api/v1/admin/users/${userId}`);
  return response.data;
};

export const lockUser = async (userId) => {
  const response = await http.post(`/api/v1/admin/users/${userId}/lock`);
  return response.data;
};

export const unlockUser = async (userId) => {
  const response = await http.post(`/api/v1/admin/users/${userId}/unlock`);
  return response.data;
};

export const banUser = async (userId, reason) => {
  const params = reason ? { reason } : {};
  const response = await http.post(`/api/v1/admin/users/${userId}/ban`, null, {
    params,
  });
  return response.data;
};

export const unbanUser = async (userId) => {
  const response = await http.post(`/api/v1/admin/users/${userId}/unban`);
  return response.data;
};

export const assignRoleToUser = async (userId, roleCode) => {
  const response = await http.post(
    `/api/v1/admin/users/${userId}/roles`,
    null,
    { params: { roleCode } }
  );
  return response.data;
};

export const resetUserPassword = async (userId) => {
  const res = await http.post(`/api/v1/admin/users/${userId}/reset-password`);
  return res.data;
};

export const fetchRoles = async (pageOrPageable = 0, size = 20) => {
  const params = normalizePageParams(pageOrPageable, size);
  const response = await http.get("/api/v1/admin/roles", { params });
  return response.data;
};

export const createRole = async (roleData) => {
  const response = await http.post("/api/v1/admin/roles", roleData);
  return response.data;
};

export const updateRole = async (roleId, roleData) => {
  const response = await http.put(`/api/v1/admin/roles/${roleId}`, roleData);
  return response.data;
};

export const deleteRole = async (roleId) => {
  const response = await http.delete(`/api/v1/admin/roles/${roleId}`);
  return response.data;
};

export const fetchPrivilegesPage = async (pageOrPageable = 0, size = 20) => {
  const params = normalizePageParams(pageOrPageable, size);
  let response;
  try {
    response = await http.get("/api/v1/admin/privileges", { params });
  } catch {
    response = await http.get("/admin/privileges", { params });
  }
  return response.data;
};

export const fetchPrivileges = async (pageOrPageable = null, size = 1000) => {
  const base =
    pageOrPageable == null
      ? {
          page: 0,
          size,
        }
      : pageOrPageable;
  const params = normalizePageParams(base, size);
  let response;
  try {
    response = await http.get("/api/v1/admin/privileges", { params });
  } catch {
    response = await http.get("/admin/privileges", { params });
  }
  const data = response.data;
  let items = [];
  if (Array.isArray(data)) {
    items = data;
  } else if (data && Array.isArray(data.content)) {
    items = data.content;
  } else if (data && data._embedded) {
    const keys = Object.keys(data._embedded);
    for (let k of keys) {
      if (Array.isArray(data._embedded[k])) {
        items = data._embedded[k];
        break;
      }
    }
  }
  return items.map((p) => ({
    id: p.privilegeId || p.id || p.uuid || p.privilege_id,
    code: p.privilegeCode || p.code || p.privilege_code,
    name: p.privilegeName || p.name || p.privilege_name,
    description:
      p.privilegeDescription || p.description || p.privilege_description,
    category: p.privilegeCategory || p.category || p.privilege_category,
    isActive:
      p.isActive !== undefined
        ? p.isActive
        : p.is_active !== undefined
        ? p.is_active
        : true,
  }));
};

export const deletePrivilege = async (privilegeId) => {
  try {
    const response = await http.delete(
      `/api/v1/admin/privileges/${privilegeId}`
    );
    return response.data;
  } catch {
    const response = await http.delete(`/admin/privileges/${privilegeId}`);
    return response.data;
  }
};

export async function sendWelcome(userId, body) {
  const res = await http.post(
    `/api/v1/admin/users/${userId}/welcome`,
    body || {}
  );
  return res.data;
}

export const addPrivilegeToRole = async (
  roleCode,
  privilegeCode,
  privilegeName
) => {
  const res = await http.post(
    `/api/v1/admin/roles/${encodeURIComponent(roleCode)}/privileges`,
    null,
    { params: { privilegeCode, privilegeName } }
  );
  return res.data;
};

export const assignPrivilegesToRoleByUpdate = async (
  roleId,
  privilegeIds = []
) => {
  const res = await http.put(`/api/v1/admin/roles/${roleId}`, {
    privilegeIds,
  });
  return res.data;
};

// 📁 src/services/testorderApi.js
import axios from "axios";

const TESTORDER_BASE =
  import.meta.env.VITE_API_TESTORDER || "https://be2.flaboratory.cloud";

// helper lấy token
const getToken = () => localStorage.getItem("lm.access");

const httpTestOrder = axios.create({
  baseURL: TESTORDER_BASE,
  withCredentials: true,
});

// tự gắn Authorization cho mỗi request
httpTestOrder.interceptors.request.use((config) => {
  const token = getToken();
  if (token) {
    config.headers = config.headers || {};
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

function normalizePageParams(p, s) {
  if (p == null && s == null) return {};
  if (p != null && typeof p === "object") {
    const page = Number.isFinite(p.page)
      ? p.page
      : Number.isFinite(p.pageNumber)
      ? p.pageNumber
      : undefined;
    const size = Number.isFinite(p.size)
      ? p.size
      : Number.isFinite(p.pageSize)
      ? p.pageSize
      : undefined;
    return {
      ...(page !== undefined ? { page } : {}),
      ...(size !== undefined ? { size } : {}),
    };
  }
  const page = Number.isFinite(p) ? p : undefined;
  const size = Number.isFinite(s) ? s : undefined;
  return {
    ...(page !== undefined ? { page } : {}),
    ...(size !== undefined ? { size } : {}),
  };
}

// GET /api/v1/test-orders
export const fetchTestOrders = async (pageOrPageable = 0, size = 20) => {
  const params = normalizePageParams(pageOrPageable, size);
  const res = await httpTestOrder.get("/api/v1/test-orders", { params });
  return res.data;
};

// GET /api/v1/test-orders/{id}
export const fetchTestOrderById = async (id) => {
  const res = await httpTestOrder.get(`/api/v1/test-orders/${id}`);
  return res.data;
};

// POST /api/v1/test-orders
export const createTestOrder = async (payload) => {
  const res = await httpTestOrder.post("/api/v1/test-orders", payload);
  return res.data;
};

// PUT /api/v1/test-orders/{id}
export const updateTestOrder = async (id, payload) => {
  const res = await httpTestOrder.put(`/api/v1/test-orders/${id}`, payload);
  return res.data;
};

// DELETE /api/v1/test-orders/{id}
export const deleteTestOrder = async (id) => {
  const res = await httpTestOrder.delete(`/api/v1/test-orders/${id}`);
  return res.data;
};

// ⭐ ADD ITEMS TO ORDER — sử dụng chung API test-order controller
export const addItemsToOrder = async (orderId, testTypeIds) => {
  const res = await httpTestOrder.post(`/api/v1/test-orders/${orderId}/items`, {
    testTypeIds,
  });
  return res.data;
};

// ⭐ DELETE ITEM from Test Order
export const deleteTestOrderItem = async (itemId) => {
  const res = await httpTestOrder.delete(`/api/v1/test-orders/items/${itemId}`);
  return res.data;
};

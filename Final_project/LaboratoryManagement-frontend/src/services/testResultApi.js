// 📁 src/services/testResultApi.js
import axios from "axios";

const TESTRESULT_BASE =
  import.meta.env.VITE_API_TESTRESULT || "https://be2.flaboratory.cloud";

// helper lấy token
const getToken = () => localStorage.getItem("lm.access");

// axios instance
const httpTestResult = axios.create({
  baseURL: TESTRESULT_BASE,
  withCredentials: true,
});

// auto attach Authorization header
httpTestResult.interceptors.request.use((config) => {
  const token = getToken();
  if (token) {
    config.headers = config.headers || {};
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// 📌 GET /api/v1/test-results
export const fetchAllTestResults = async () => {
  const res = await httpTestResult.get("/api/v1/test-results");
  return res.data;
};

// 📌 GET /api/v1/test-results/{id}
export const fetchTestResultById = async (id) => {
  const res = await httpTestResult.get(`/api/v1/test-results/${id}`);
  return res.data;
};

// 📌 GET /api/v1/test-results/by-item/{itemId}
export const fetchResultsByItemId = async (itemId) => {
  const res = await httpTestResult.get(`/api/v1/test-results/by-item/${itemId}`);
  return res.data;
};

// 📌 POST /api/v1/test-results  → CREATE RESULT
export const createTestResult = async (payload) => {
  const res = await httpTestResult.post(`/api/v1/test-results`, payload);
  return res.data;
};

// 📌 PUT /api/v1/test-results/{id}  → UPDATE RESULT
export const updateTestResult = async (id, payload) => {
  const res = await httpTestResult.put(`/api/v1/test-results/${id}`, payload);
  return res.data;
};

// 📌 DELETE /api/v1/test-results/{id}
export const deleteTestResult = async (id) => {
  const res = await httpTestResult.delete(`/api/v1/test-results/${id}`);
  return res.data;
};

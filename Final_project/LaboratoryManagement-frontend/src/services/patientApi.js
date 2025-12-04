// src/services/patientApi.js
import { createApiWithBase } from "../lib/api";

const BE_BASE =
  import.meta.env.VITE_API_TESTORDER_PATIENT || "https://be2.flaboratory.cloud";
const api = createApiWithBase(BE_BASE);

const BASE = "/api/v1/patients";

export const getAllPatients = (params) => api.get(BASE, { params });

export const getPatient = (id) => api.get(`${BASE}/${id}`);

export const searchPatientsByName = (name) =>
  api.get(`${BASE}/search`, { params: { name } });

export const createPatient = (payload) => api.post(BASE, payload);

export const updatePatient = (id, payload) => api.put(`${BASE}/${id}`, payload);

export const deletePatient = (id) => api.delete(`${BASE}/${id}`);


export default {
  getAllPatients,
  getPatient,
  searchPatientsByName,
  createPatient,
  updatePatient,
  deletePatient,
};

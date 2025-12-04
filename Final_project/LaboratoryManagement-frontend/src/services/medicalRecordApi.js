import http from "../lib/api"; // Sử dụng instance axios đã cấu hình sẵn base URL

const BE_BASE =
  import.meta.env.VITE_API_TESTORDER_PATIENT || "https://be2.flaboratory.cloud";

export const getSystemMedicalRecords = async (params) => {
  try {
    const response = await http.get(
      `${BE_BASE}/api/v1/patient/all-medical-records`,
      { params }
    );
    return response.data;
  } catch (error) {
    console.error("Error fetching system medical records:", error);
    throw error;
  }
};

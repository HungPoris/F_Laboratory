// config/menus/labManagerMenu.js
import { ClipboardList, FileCheck, Users, FileText } from "lucide-react";

const labManagerMenu = [
  {
    to: "/patients",
    label: "Patients",
    Icon: Users,
    screenCode: "PATIENT_LIST",
  },
  {
    to: "/patients/all-medical-records",
    label: "All Medical Records",
    Icon: FileText,
    screenCode: "ALL_MEDICAL_RECORDS",
  },
];

export default labManagerMenu;

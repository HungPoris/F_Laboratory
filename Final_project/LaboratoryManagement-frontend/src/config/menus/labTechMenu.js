import { ClipboardList, Beaker, Cpu, Users } from "lucide-react";

const labTechMenu = [
  {
    to: "/patients",
    label: "Patients",
    Icon: Users,
    screenCode: "PATIENT_LIST",
  },
  {
    to: "/patients/all-medical-records",
    label: "All Medical Records",
    Icon: Beaker,
    screenCode: "ALL_MEDICAL_RECORDS",
  },
];

export default labTechMenu;

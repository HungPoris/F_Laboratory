import { Users, Shield, Key } from "lucide-react";

const adminMenu = [
  {
    to: "/admin/users",
    label: "Users",
    Icon: Users,
    screenCode: "ADMIN_USERS_LIST",
  },
  {
    to: "/admin/roles",
    label: "Role",
    Icon: Shield,
    screenCode: "ADMIN_ROLES_LIST",
  },
  {
    to: "/admin/privileges",
    label: "Privileges",
    Icon: Key,
    screenCode: "ADMIN_PRIVILEGES_LIST",
  },
];

export default adminMenu;

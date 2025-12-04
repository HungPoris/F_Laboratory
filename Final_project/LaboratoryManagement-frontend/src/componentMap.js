const componentMap = {
  LandingPage: () =>
    import("./pages/LandingPage.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  Login: () =>
    import("./pages/Login.jsx").catch(() => import("./pages/Placeholder.jsx")),

  AdminLogin: () =>
    import("./pages/AdminLogin").catch(() => import("./pages/Placeholder.jsx")),
  ADMIN_LOGIN: () =>
    import("./pages/AdminLogin").catch(() => import("./pages/Placeholder.jsx")),

  ChangePasswordFirstLogin: () =>
    import("./pages/ChangePasswordFirstLogin.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  CHANGE_PASSWORD_FIRST_LOGIN: () =>
    import("./pages/ChangePasswordFirstLogin.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),

  UsersList: () =>
    import("./pages/ADMIN/UsersList.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  AdminUsersList: () =>
    import("./pages/ADMIN/UsersList.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),

  CreateUser: () =>
    import("./pages/ADMIN/CreateUser.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  AdminCreateUser: () =>
    import("./pages/ADMIN/CreateUser.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),

  RolesList: () =>
    import("./pages/ADMIN/RolesList.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  Roles: () =>
    import("./pages/ADMIN/RolesList.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  AdminRoles: () =>
    import("./pages/ADMIN/RolesList.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  ADMIN_ROLES: () =>
    import("./pages/ADMIN/RolesList.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  AdminRolesList: () =>
    import("./pages/ADMIN/RolesList.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),

  PrivilegesList: () =>
    import("./pages/ADMIN/PrivilegesList.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  Privileges: () =>
    import("./pages/ADMIN/PrivilegesList.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  AdminPrivileges: () =>
    import("./pages/ADMIN/PrivilegesList.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  ADMIN_PRIVILEGES: () =>
    import("./pages/ADMIN/PrivilegesList.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  AdminPrivilegesList: () =>
    import("./pages/ADMIN/PrivilegesList.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),

  ADMIN_USERS_LIST: () =>
    import("./pages/ADMIN/UsersList.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  ADMIN_ROLES_LIST: () =>
    import("./pages/ADMIN/RolesList.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  ADMIN_PRIVILEGES_LIST: () =>
    import("./pages/ADMIN/PrivilegesList.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),

  EditUser: () =>
    import("./pages/ADMIN/EditUser.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  AdminEditUser: () =>
    import("./pages/ADMIN/EditUser.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  ADMIN_EDIT_USER: () =>
    import("./pages/ADMIN/EditUser.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  ProfileLayout: () =>
    import("./layouts/ProfileLayout.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  Profile: () =>
    import("./pages/CommonPage/Profile.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  UpdateProfile: () =>
    import("./pages/CommonPage/UpdateProfile.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  ChangePassword: () =>
    import("./pages/CommonPage/ChangePassword.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  Forbidden403: () =>
    import("./pages/Forbidden403.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),

  NotFound: () =>
    import("./pages/NotFound.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  Placeholder: () => import("./pages/Placeholder.jsx"),

  PATIENTS: () =>
    import("./pages/PATIENTS/PatientList.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),

  PatientList: () =>
    import("./pages/PATIENTS/PatientList.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  PATIENT_LIST: () =>
    import("./pages/PATIENTS/PatientList.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),

  PatientDetail: () =>
    import("./pages/PATIENTS/PatientDetail.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  PATIENT_DETAIL: () =>
    import("./pages/PATIENTS/PatientDetail.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),

  PatientAdd: () =>
    import("./pages/PATIENTS/PatientAdd.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  PatientCreate: () =>
    import("./pages/PATIENTS/PatientAdd.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  PATIENT_CREATE: () =>
    import("./pages/PATIENTS/PatientAdd.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),

  PatientEdit: () =>
    import("./pages/PATIENTS/PatientEdit.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  PATIENT_EDIT: () =>
    import("./pages/PATIENTS/PatientEdit.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),

  MedicalRecordDetail: () =>
    import("./pages/PATIENTS/MedicalRecordDetail.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  MEDICAL_RECORD_DETAIL: () =>
    import("./pages/PATIENTS/MedicalRecordDetail.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  AllMedicalRecords: () =>
    import("./pages/PATIENTS/AllMedicalRecords.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  ALL_MEDICAL_RECORDS: () =>
    import("./pages/PATIENTS/AllMedicalRecords.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  LAB_TEST_ORDER_CREATE: () =>
    import("./pages/TEST_ORDER/TestOrderCreate.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),

  TestOrderList: () =>
    import("./pages/TEST_ORDER/TestOrderList.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  TEST_ORDER_LIST: () =>
    import("./pages/TEST_ORDER/TestOrderList.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  TEST_ORDERS: () =>
    import("./pages/TEST_ORDER/TestOrderList.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  TESTORDERS: () =>
    import("./pages/TEST_ORDER/TestOrderList.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  SCR_TEST_ORDERS: () =>
    import("./pages/TEST_ORDER/TestOrderList.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),

  TestOrderEdit: () =>
    import("./pages/TEST_ORDER/TestOrderedit.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  TEST_ORDER_EDIT: () =>
    import("./pages/TEST_ORDER/TestOrderedit.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),

  TestOrderDetail: () =>
    import("./pages/TEST_ORDER/TestOrderDetail.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  TEST_ORDER_DETAIL: () =>
    import("./pages/TEST_ORDER/TestOrderDetail.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),

  TestOrderCreate: () =>
    import("./pages/TEST_ORDER/TestOrderCreate.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  TEST_ORDER_CREATE: () =>
    import("./pages/TEST_ORDER/TestOrderCreate.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),

  TestResultList: () =>
    import("./pages/TEST_RESULT/TestResultList.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  TEST_RESULT_LIST: () =>
    import("./pages/TEST_RESULT/TestResultList.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  TEST_RESULTS: () =>
    import("./pages/TEST_RESULT/TestResultList.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  SCR_TEST_RESULTS: () =>
    import("./pages/TEST_RESULT/TestResultList.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  MedicalRecordCreate: () =>
    import("./pages/PATIENTS/MedicalRecordCreate.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  MEDICAL_RECORD_CREATE: () =>
    import("./pages/PATIENTS/MedicalRecordCreate.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),

  MedicalRecordEdit: () =>
    import("./pages/PATIENTS/MedicalRecordEdit.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  MEDICAL_RECORD_EDIT: () =>
    import("./pages/PATIENTS/MedicalRecordEdit.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),

  MedicalRecordView: () =>
    import("./pages/PATIENTS/MedicalRecordDetail.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
  MEDICAL_RECORD_VIEW: () =>
    import("./pages/PATIENTS/MedicalRecordDetail.jsx").catch(() =>
      import("./pages/Placeholder.jsx")
    ),
};

export default componentMap;

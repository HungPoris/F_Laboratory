import React, { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import { useNavigate } from "react-router-dom";
import http from "../../lib/api";
import { useAuth } from "../../lib";
import {
  User,
  Mail,
  Phone,
  Calendar,
  CreditCard,
  MapPin,
  UserCheck,
} from "lucide-react";
import Loading from "../../components/Loading";

export default function Profile() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const { user } = useAuth() || {};
  const [loading, setLoading] = useState(true);
  const [profile, setProfile] = useState({
    username: user?.username || "",
    fullName: user?.fullName || "",
    email: user?.raw?.email || user?.email || "",
    phoneNumber: "",
    dateOfBirth: "",
    identityNumber: "",
    gender: "",
    address: "",
  });

  useEffect(() => {
    let mounted = true;
    async function load() {
      setLoading(true);
      try {
        const res =
          (await http.get("/api/v1/profile").catch(() => null)) ||
          (await http.get("/api/v1/auth/me").catch(() => null));
        const d = res?.data || {};
        const p = {
          username: d.username || user?.username || "",
          fullName: d.fullName || user?.fullName || d.name || "",
          email: d.email || user?.raw?.email || user?.email || "",
          phoneNumber: d.phoneNumber || d.phone || "",
          dateOfBirth: d.dateOfBirth || d.dob || "",
          identityNumber: d.identityNumber || d.identity || "",
          gender: (d.gender || "").toString().toUpperCase(),
          address: d.address || d.fullAddress || "",
        };
        if (mounted) setProfile(p);
      } finally {
        if (mounted) setLoading(false);
      }
    }
    load();
    return () => {
      mounted = false;
    };
  }, [user?.username, user?.fullName, user?.email]);

  return (
    <>
      <style>{`
        @keyframes fade-in{from{opacity:.0;transform:translateY(10px)}to{opacity:1;transform:translateY(0)}}
        .fade-in{animation:fade-in .5s ease-out}
        input[readonly] {
          background-color: white !important;
          cursor: default;
        }
        input[readonly]:focus {
          background-color: white !important;
        }
      `}</style>

      <div className="fade-in">
        <div className="flex items-center gap-3 mb-8">
          <div className="p-3 rounded-2xl bg-gradient-to-br from-emerald-500 to-sky-600">
            <UserCheck className="w-8 h-8 text-white" />
          </div>
          <div>
            <h1 className="text-3xl font-bold bg-gradient-to-r from-emerald-600 to-sky-600 bg-clip-text text-transparent">
              My Profile
            </h1>
            <p className="text-sm text-gray-500 mt-1">
              Your account information
            </p>
          </div>
        </div>

        {loading ? (
          <div className="py-16 flex items-center justify-center">
            <Loading size={48} />
          </div>
        ) : (
          <div className="space-y-8">
            <div className="space-y-4">
              <h3 className="text-lg font-semibold text-gray-700 flex items-center gap-2">
                <User className="w-5 h-5 text-emerald-500" />
                {t("admin.login_info")}
              </h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    {t("admin.full_name")}
                  </label>
                  <div className="relative">
                    <User className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                    <input
                      value={profile.fullName}
                      readOnly
                      className="w-full rounded-xl border-2 border-gray-200 pl-10 pr-4 py-3 bg-white focus:border-emerald-500 focus:outline-none transition-colors"
                    />
                  </div>
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    {t("admin.username")}
                  </label>
                  <div className="relative">
                    <User className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                    <input
                      value={profile.username}
                      readOnly
                      className="w-full rounded-xl border-2 border-gray-200 pl-10 pr-4 py-3 bg-white focus:border-emerald-500 focus:outline-none transition-colors"
                    />
                  </div>
                </div>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  {t("admin.email")}
                </label>
                <div className="relative">
                  <Mail className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                  <input
                    value={profile.email}
                    readOnly
                    className="w-full rounded-xl border-2 border-gray-200 pl-10 pr-4 py-3 bg-white focus:border-emerald-500 focus:outline-none transition-colors"
                  />
                </div>
              </div>
            </div>

            <div className="space-y-4 pt-6 border-t">
              <h3 className="text-lg font-semibold text-gray-700 flex items-center gap-2">
                <CreditCard className="w-5 h-5 text-sky-500" />
                {t("admin.personal_info")}
              </h3>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    {t("admin.phone_number")}
                  </label>
                  <div className="relative">
                    <Phone className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                    <input
                      value={profile.phoneNumber || ""}
                      readOnly
                      className="w-full rounded-xl border-2 border-gray-200 pl-10 pr-4 py-3 bg-white focus:border-emerald-500 focus:outline-none transition-colors"
                    />
                  </div>
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    {t("admin.date_of_birth")}
                  </label>
                  <div className="relative">
                    <Calendar className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                    <input
                      type="date"
                      value={profile.dateOfBirth || ""}
                      readOnly
                      className="w-full rounded-xl border-2 border-gray-200 pl-10 pr-4 py-3 bg-white focus:border-emerald-500 focus:outline-none transition-colors"
                    />
                  </div>
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    {t("Citizen ID / Passport Number")}
                  </label>
                  <div className="relative">
                    <CreditCard className="absolute left-3 top-3.5 w-5 h-5 text-gray-400 pointer-events-none" />
                    <input
                      value={
                        profile.identityNumber || "Citizen ID / Passport Number"
                      }
                      readOnly
                      className="w-full rounded-xl border-2 border-gray-200 pl-10 pr-4 py-3 bg-white focus:border-emerald-500 focus:outline-none transition-colors"
                    />
                  </div>
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    {t("admin.gender")}
                  </label>
                  <input
                    value={profile.gender || ""}
                    readOnly
                    className="w-full rounded-xl border-2 border-gray-200 px-4 py-3 bg-white focus:border-emerald-500 focus:outline-none transition-colors"
                  />
                </div>
              </div>
            </div>

            <div className="space-y-4 pt-6 border-t">
              <h3 className="text-lg font-semibold text-gray-700 flex items-center gap-2">
                <MapPin className="w-5 h-5 text-emerald-500" />
                Current Address
              </h3>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Address
                </label>
                <input
                  value={profile.address || ""}
                  readOnly
                  className="w-full rounded-xl border-2 border-gray-200 px-4 py-3 bg-white focus:border-emerald-500 focus:outline-none transition-colors"
                />
              </div>
            </div>

            <div className="flex items-center justify-end pt-6 border-t">
              <button
                type="button"
                onClick={() => navigate("/profile/update")}
                className="px-6 py-3 rounded-xl text-white font-medium shadow-lg transition-all bg-gradient-to-r from-emerald-500 to-sky-600 hover:from-sky-600 hover:to-emerald-500 hover:shadow-xl"
              >
                Update Profile
              </button>
            </div>
          </div>
        )}
      </div>
    </>
  );
}

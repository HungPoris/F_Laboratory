import { toast } from "react-toastify";
import Swal from "sweetalert2";

export function toastify(message) {
  if (!message && typeof message !== "string") message = String(message);
  toast(String(message), { position: "top-right", autoClose: 4000 });
}
export function success(message) {
  toast.success(String(message), { position: "top-right", autoClose: 3500 });
}
export function info(message) {
  toast.info(String(message), { position: "top-right", autoClose: 3500 });
}
export function warn(message) {
  toast.warn(String(message), { position: "top-right", autoClose: 4500 });
}
export function error(message) {
  toast.error(String(message), { position: "top-right", autoClose: 5000 });
}
export function modalError(title, message) {
  Swal.fire({ icon: "error", title: title || "Lỗi", text: String(message) });
}
export function modalSuccess(title, message) {
  Swal.fire({
    icon: "success",
    title: title || "Thành công",
    text: String(message),
  });
}

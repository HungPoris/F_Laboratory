export function stripParams(path) {
  if (!path) return path;
  return path.replace(/\/:[^/]+/g, "");
}
export function matchBasePath(base, pathname) {
  if (!base) return false;
  if (base === "/") return pathname === "/" || pathname === "";
  if (pathname === base) return true;
  if (pathname.startsWith(base + "/")) return true;
  return false;
}
const ROUTE_UTIL = { stripParams, matchBasePath };
export default ROUTE_UTIL;

export function getTokenExpiry(token) {
  if (!token || typeof token !== "string") return null;

  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;

    const payload = JSON.parse(atob(parts[1]));
    return payload.exp ? payload.exp * 1000 : null;
  } catch {
    return null;
  }
}

export function isTokenExpiringSoon(token, bufferMs = 60000) {
  const expiry = getTokenExpiry(token);
  if (!expiry) return true;

  const now = Date.now();
  const timeUntilExpiry = expiry - now;
  return timeUntilExpiry < bufferMs;
}

export function isTokenExpired(token) {
  const expiry = getTokenExpiry(token);
  if (!expiry) return true;
  return Date.now() >= expiry;
}

export function getTokenRemainingTime(token) {
  const expiry = getTokenExpiry(token);
  if (!expiry) return 0;

  const now = Date.now();
  const remaining = expiry - now;
  return Math.max(0, remaining);
}

export function getTokenLifetimePercentage(token) {
  if (!token) return 0;

  try {
    const parts = token.split(".");
    if (parts.length !== 3) return 0;

    const payload = JSON.parse(atob(parts[1]));
    if (!payload.exp || !payload.iat) return 0;

    const now = Date.now() / 1000;
    const lifetime = payload.exp - payload.iat;
    const elapsed = now - payload.iat;
    const remaining = payload.exp - now;

    if (remaining <= 0) return 0;
    if (elapsed <= 0) return 100;

    return Math.max(0, Math.min(100, (remaining / lifetime) * 100));
  } catch {
    return 0;
  }
}

export function formatRemainingTime(milliseconds) {
  if (milliseconds <= 0) return "expired";

  const seconds = Math.floor(milliseconds / 1000);
  const minutes = Math.floor(seconds / 60);
  const hours = Math.floor(minutes / 60);
  const days = Math.floor(hours / 24);

  if (days > 0) return `${days} day${days > 1 ? "s" : ""}`;
  if (hours > 0) return `${hours} hour${hours > 1 ? "s" : ""}`;
  if (minutes > 0) return `${minutes} minute${minutes > 1 ? "s" : ""}`;
  return `${seconds} second${seconds !== 1 ? "s" : ""}`;
}

export function logTokenInfo() {}

package fpt.com.laboratorymanagementbackend.security.cloudflare;

import jakarta.servlet.http.HttpServletRequest;

public class CloudflareClientResolver {
    private final boolean enabled;
    private final String header;

    public CloudflareClientResolver(boolean enabled, String header) {
        this.enabled = enabled;
        this.header = header;
    }

    public String resolveClientIp(HttpServletRequest req) {
        if (!enabled) return req.getRemoteAddr();
        String h = req.getHeader(header);
        if (h != null && !h.isBlank()) return h.split(",")[0].trim();
        String xf = req.getHeader("X-Forwarded-For");
        if (xf != null && !xf.isBlank()) return xf.split(",")[0].trim();
        return req.getRemoteAddr();
    }
}


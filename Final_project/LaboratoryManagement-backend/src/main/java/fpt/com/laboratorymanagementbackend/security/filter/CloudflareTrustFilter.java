package fpt.com.laboratorymanagementbackend.security.filter;

import org.springframework.web.filter.OncePerRequestFilter;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpServletRequestWrapper;
import java.io.IOException;

public class CloudflareTrustFilter extends OncePerRequestFilter {
    private final boolean enabled;
    private final String clientIpHeader;

    public CloudflareTrustFilter(boolean enabled, String clientIpHeader) {
        this.enabled = enabled;
        this.clientIpHeader = clientIpHeader;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return !enabled;
    }

    private String pickFirstIp(String headerValue) {
        if (headerValue == null) return null;
        String[] parts = headerValue.split(",");
        if (parts.length == 0) return headerValue.trim();
        return parts[0].trim();
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain) throws ServletException, IOException {
        if (!enabled) {
            filterChain.doFilter(request, response);
            return;
        }
        String cfIp = pickFirstIp(request.getHeader(clientIpHeader));
        if (cfIp == null || cfIp.isBlank()) {
            filterChain.doFilter(request, response);
            return;
        }
        HttpServletRequest wrapped = new RemoteAddressRequestWrapper(request, cfIp);
        filterChain.doFilter(wrapped, response);
    }

    private static class RemoteAddressRequestWrapper extends HttpServletRequestWrapper {
        private final String remoteAddr;
        public RemoteAddressRequestWrapper(HttpServletRequest request, String remoteAddr) {
            super(request);
            this.remoteAddr = remoteAddr;
        }
        @Override
        public String getRemoteAddr() {
            return remoteAddr;
        }
    }
}

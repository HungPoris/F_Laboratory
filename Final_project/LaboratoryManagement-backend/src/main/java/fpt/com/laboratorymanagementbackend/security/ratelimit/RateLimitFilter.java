package fpt.com.laboratorymanagementbackend.security.ratelimit;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.authentication.AnonymousAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.filter.OncePerRequestFilter;
import java.io.IOException;
import java.util.Set;
import fpt.com.laboratorymanagementbackend.security.cloudflare.CloudflareClientResolver;

public class RateLimitFilter extends OncePerRequestFilter {
    private static final Logger log = LoggerFactory.getLogger(RateLimitFilter.class);

    private final RateLimitService rateLimitService;
    private final int maxRequests;
    private final int windowSeconds;
    private final Set<String> protectedPaths;
    private final CloudflareClientResolver resolver;
    private final String redisKeyPrefix;

    public RateLimitFilter(
            RateLimitService rateLimitService,
            int maxRequests,
            int windowSeconds,
            Set<String> protectedPaths,
            CloudflareClientResolver resolver,
            String redisKeyPrefix) {
        this.rateLimitService = rateLimitService;
        this.maxRequests = maxRequests;
        this.windowSeconds = windowSeconds;
        this.protectedPaths = protectedPaths;
        this.resolver = resolver;
        this.redisKeyPrefix = redisKeyPrefix != null ? redisKeyPrefix : "app";
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String method = request.getMethod();
        if ("OPTIONS".equalsIgnoreCase(method)) return true;
        String path = request.getRequestURI();
        return protectedPaths.stream().noneMatch(path::startsWith);
    }


    private void writeJsonError(HttpServletResponse response, int status, String error) throws IOException {
        response.setStatus(status);
        response.setContentType("application/json");
        response.setCharacterEncoding("utf-8");
        response.getWriter().write("{\"error\":\"" + error + "\"}");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {

        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth != null && auth.isAuthenticated() && !(auth instanceof AnonymousAuthenticationToken)) {
            chain.doFilter(request, response);
            return;
        }

        String ip = resolver != null ? resolver.resolveClientIp(request) : request.getRemoteAddr();
        String key = redisKeyPrefix + ":ratelimit:auth:ip:" + ip;

        boolean allowed = rateLimitService.isAllowed(key, maxRequests, windowSeconds);

        if (!allowed) {
            writeJsonError(response, 429, "rate_limited");
            return;
        }

        chain.doFilter(request, response);
    }
}

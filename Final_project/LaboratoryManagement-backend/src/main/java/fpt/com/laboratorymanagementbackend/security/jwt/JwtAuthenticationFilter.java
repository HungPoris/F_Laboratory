package fpt.com.laboratorymanagementbackend.security.jwt;

import fpt.com.laboratorymanagementbackend.security.userdetails.CustomUserDetailsService;
import fpt.com.laboratorymanagementbackend.security.userdetails.UserPrincipal;
import fpt.com.laboratorymanagementbackend.common.service.JwtBlacklistService;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.ExpiredJwtException;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource;
import org.springframework.util.StringUtils;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.Date;
import java.util.Optional;

public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private final JwtUtil jwtUtil;
    private final CustomUserDetailsService uds;
    private final StringRedisTemplate redis;
    private final String blacklistPrefix;
    private final JwtBlacklistService jwtBlacklistService;
    private final String userTokensPrefix;

    public JwtAuthenticationFilter(JwtUtil jwtUtil,
                                   CustomUserDetailsService uds,
                                   StringRedisTemplate redis,
                                   String blacklistPrefix,
                                   JwtBlacklistService jwtBlacklistService,
                                   String userTokensPrefix) {
        this.jwtUtil = jwtUtil;
        this.uds = uds;
        this.redis = redis;
        this.blacklistPrefix = blacklistPrefix == null ? "" : (blacklistPrefix.endsWith(":") ? blacklistPrefix : blacklistPrefix + ":");
        this.jwtBlacklistService = jwtBlacklistService;
        this.userTokensPrefix = userTokensPrefix == null ? "" : (userTokensPrefix.endsWith(":") ? userTokensPrefix : userTokensPrefix + ":");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {
        String header = request.getHeader("Authorization");
        if (!StringUtils.hasText(header) || !header.startsWith("Bearer ")) {
            filterChain.doFilter(request, response);
            return;
        }

        String token = header.substring(7).trim();
        if (!StringUtils.hasText(token)) {
            filterChain.doFilter(request, response);
            return;
        }

        Claims claims;
        try {
            claims = jwtUtil.parseClaims(token);
        } catch (ExpiredJwtException eje) {
            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            response.getWriter().write("{\"error\":\"token_expired\"}");
            response.getWriter().flush();
            return;
        } catch (Exception e) {
            filterChain.doFilter(request, response);
            return;
        }

        String jti = claims.getId();
        if (jti != null) {
            boolean blacklisted = false;
            try {
                if (jwtBlacklistService != null && jwtBlacklistService.isBlacklisted(jti)) {
                    blacklisted = true;
                }
            } catch (Throwable ignored) {}
            if (!blacklisted && redis != null) {
                try {
                    String v = redis.opsForValue().get(blacklistPrefix + jti);
                    if (v != null) blacklisted = true;
                } catch (Throwable ignored) {}
            }
            if (blacklisted) {
                response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
                response.getWriter().write("{\"error\":\"token_revoked\"}");
                response.getWriter().flush();
                return;
            }
        }

        String sub = claims.getSubject();
        if (sub == null) {
            filterChain.doFilter(request, response);
            return;
        }

        Optional<UserPrincipal> ou;
        try {
            ou = uds.loadByUsernameOrEmail(sub);
        } catch (Exception e) {
            filterChain.doFilter(request, response);
            return;
        }
        if (ou.isEmpty()) {
            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            response.getWriter().write("{\"error\":\"user_not_found\"}");
            response.getWriter().flush();
            return;
        }

        UserPrincipal up = ou.get();

        try {
            if (redis != null) {
                String revokedAt = redis.opsForValue().get(userTokensPrefix + up.getId() + ":revoked_at");
                if (revokedAt != null) {
                    long revokedEpoch = Long.parseLong(revokedAt);
                    Date iat = claims.getIssuedAt();
                    long iatEpoch = (iat != null) ? (iat.getTime() / 1000) : 0L;
                    if (iatEpoch > 0 && iatEpoch < revokedEpoch) {
                        response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
                        response.getWriter().write("{\"error\":\"token_revoked_userwide\"}");
                        response.getWriter().flush();
                        return;
                    }
                }
            }
        } catch (Throwable ignored) {}

        UsernamePasswordAuthenticationToken auth =
                new UsernamePasswordAuthenticationToken(up, null, up.getAuthorities());
        auth.setDetails(new WebAuthenticationDetailsSource().buildDetails(request));
        SecurityContextHolder.getContext().setAuthentication(auth);

        filterChain.doFilter(request, response);
    }
}

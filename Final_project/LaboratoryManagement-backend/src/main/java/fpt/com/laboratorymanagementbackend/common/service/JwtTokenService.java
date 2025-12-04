package fpt.com.laboratorymanagementbackend.common.service;

import fpt.com.laboratorymanagementbackend.security.jwt.JwtUtil;
import fpt.com.laboratorymanagementbackend.security.userdetails.CustomUserDetailsService;
import fpt.com.laboratorymanagementbackend.security.userdetails.UserPrincipal;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.stereotype.Service;

import java.util.Collection;
import java.util.Optional;
import java.util.UUID;

@Service
public class JwtTokenService {

    private final JwtUtil jwtUtil;
    private final JwtBlacklistService jwtBlacklistService;
    private final CustomUserDetailsService customUserDetailsService;

    public JwtTokenService(JwtUtil jwtUtil,
                           JwtBlacklistService jwtBlacklistService,
                           CustomUserDetailsService customUserDetailsService) {
        this.jwtUtil = jwtUtil;
        this.jwtBlacklistService = jwtBlacklistService;
        this.customUserDetailsService = customUserDetailsService;
    }

    public String issueAccessTokenForUser(String subject, String userId) {
        Collection<? extends GrantedAuthority> authorities = null;
        try {
            Optional<UserPrincipal> userPrincipal = customUserDetailsService.loadByUsernameOrEmail(subject);
            if (userPrincipal.isPresent()) {
                authorities = userPrincipal.get().getAuthorities();
            }
        } catch (Exception ignored) {}
        String token = jwtUtil.generateAccessToken(subject, UUID.randomUUID().toString(), authorities);
        String jti = jwtUtil.parseClaims(token).getId();
        long ttl = jwtUtil.getAccessTokenTtlSeconds();
        jwtBlacklistService.recordTokenForUser(userId, jti, ttl);
        return token;
    }
}

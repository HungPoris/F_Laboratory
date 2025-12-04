package fpt.com.laboratorymanagementbackend.domain.iam.auth.controller;

import fpt.com.laboratorymanagementbackend.common.service.JwtTokenService;
import fpt.com.laboratorymanagementbackend.common.service.OutboxService;
import fpt.com.laboratorymanagementbackend.domain.iam.auth.dto.AuthFailureResponse;
import fpt.com.laboratorymanagementbackend.domain.iam.auth.dto.LoginRequest;
import fpt.com.laboratorymanagementbackend.domain.iam.refresh.entity.RefreshToken;
import fpt.com.laboratorymanagementbackend.domain.iam.refresh.service.RefreshTokenService;
import fpt.com.laboratorymanagementbackend.domain.iam.user.entity.User;
import fpt.com.laboratorymanagementbackend.domain.iam.user.service.UserService;
import fpt.com.laboratorymanagementbackend.domain.iam.user.repository.UserRepository;
import fpt.com.laboratorymanagementbackend.security.failedlogin.FailedLoginService;
import fpt.com.laboratorymanagementbackend.security.jwt.JwtUtil;
import fpt.com.laboratorymanagementbackend.common.service.JwtBlacklistService;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.ExpiredJwtException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.ResponseEntity;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.util.Optional;
import java.util.Map;
import java.util.HashMap;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {

    private static final Logger log = LoggerFactory.getLogger(AuthController.class);

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final FailedLoginService failedLoginService;
    private final JwtTokenService jwtTokenService;
    private final OutboxService outboxService;
    private final UserService userService;
    private final JwtUtil jwtUtil;
    private final JwtBlacklistService jwtBlacklistService;
    private final RefreshTokenService refreshTokenService;

    public AuthController(UserRepository userRepository,
                          PasswordEncoder passwordEncoder,
                          FailedLoginService failedLoginService,
                          JwtTokenService jwtTokenService,
                          OutboxService outboxService,
                          UserService userService,
                          JwtUtil jwtUtil,
                          JwtBlacklistService jwtBlacklistService,
                          RefreshTokenService refreshTokenService) {
        this.userRepository = userRepository;
        this.passwordEncoder = passwordEncoder;
        this.failedLoginService = failedLoginService;
        this.jwtTokenService = jwtTokenService;
        this.outboxService = outboxService;
        this.userService = userService;
        this.jwtUtil = jwtUtil;
        this.jwtBlacklistService = jwtBlacklistService;
        this.refreshTokenService = refreshTokenService;
    }

    @PostMapping("/login")
    @Transactional
    public ResponseEntity<?> login(@Valid @RequestBody LoginRequest req, HttpServletRequest servletRequest) {
        String name = req.getUsername().trim();
        Optional<User> maybe = userRepository.findByUsernameIgnoreCase(name);
        if (maybe.isEmpty()) {
            failedLoginService.incrementFailedAttempts(name);
            outboxService.publish("lab.audit.events", Map.of("event","LOGIN_FAILED_UNKNOWN","username",name));
            return ResponseEntity.status(401).body(new AuthFailureResponse("INVALID_CREDENTIALS"));
        }
        User user = maybe.get();
        if (failedLoginService.isLocked(user.getUserId()) || failedLoginService.isUsernameOrEmailLockedOrDisabled(user.getUsername(), user.getEmail())) {
            outboxService.publish("lab.audit.events", Map.of("event","LOGIN_BLOCKED_LOCKED","user_id", user.getUserId().toString(), "username", user.getUsername()));
            return ResponseEntity.status(423).body(new AuthFailureResponse("ACCOUNT_LOCKED_OR_DISABLED"));
        }
        if (!passwordEncoder.matches(req.getPassword(), user.getPasswordHash())) {
            boolean lockedNow = failedLoginService.checkAndHandleFailure(user.getUsername());
            outboxService.publish("lab.audit.events", Map.of("event","LOGIN_FAILED_BAD_PASSWORD","user_id", user.getUserId().toString(), "username", user.getUsername()));
            if (lockedNow) {
                outboxService.publish("lab.audit.events", Map.of("event","USER_TEMP_LOCKED","user_id", user.getUserId().toString(), "username", user.getUsername()));
                return ResponseEntity.status(423).body(new AuthFailureResponse("ACCOUNT_LOCKED"));
            }
            return ResponseEntity.status(401).body(new AuthFailureResponse("INVALID_CREDENTIALS"));
        }
        failedLoginService.clearFailedAttempts(user.getUsername());

        String token = jwtTokenService.issueAccessTokenForUser(user.getUsername(), user.getUserId().toString());

        String refreshToken = null;
        try {
            Claims claims = jwtUtil.parseClaims(token);
            String jti = claims.getId();
            String ip = servletRequest.getRemoteAddr();
            String ua = servletRequest.getHeader("User-Agent");
            refreshToken = refreshTokenService.createRefreshToken(user.getUserId(), jti, ip, ua);
        } catch (Exception e) {
            log.error("Failed to create refresh token", e);
        }

        outboxService.publish("lab.audit.events", Map.of("event","LOGIN_SUCCESS","user_id", user.getUserId().toString(), "username", user.getUsername()));

        Map<String, Object> response = new HashMap<>();
        response.put("token", token);
        response.put("accessToken", token);
        if (refreshToken != null) {
            response.put("refreshToken", refreshToken);
        }

        response.put("mustChangePassword", user.getMustChangePassword() != null ? user.getMustChangePassword() : false);

        Map<String, Object> userInfo = new HashMap<>();
        userInfo.put("userId", user.getUserId().toString());
        userInfo.put("username", user.getUsername());
        userInfo.put("email", user.getEmail());
        userInfo.put("fullName", user.getFullName());
        userInfo.put("mustChangePassword", user.getMustChangePassword() != null ? user.getMustChangePassword() : false);

        java.util.List<String> rolesList = user.getRoles().stream()
                .map(fpt.com.laboratorymanagementbackend.domain.iam.role.entity.Role::getRoleCode)
                .collect(java.util.stream.Collectors.toList());
        userInfo.put("roles", rolesList);
        response.put("roles", rolesList);

        response.put("user", userInfo);

        return ResponseEntity.ok(response);
    }

    @PostMapping("/refresh")
    @Transactional
    public ResponseEntity<?> refresh(@RequestBody(required = false) Map<String, String> body, HttpServletRequest request) {
        try {
            String refreshToken = null;

            if (body != null && body.containsKey("refreshToken")) {
                refreshToken = body.get("refreshToken");
            }

            if ((refreshToken == null || refreshToken.trim().isEmpty())) {
                String hdr = request.getHeader("X-Refresh-Token");
                if (hdr != null && !hdr.isBlank()) {
                    refreshToken = hdr;
                }
            }

            if ((refreshToken == null || refreshToken.trim().isEmpty())) {
                if (request.getCookies() != null) {
                    for (jakarta.servlet.http.Cookie c : request.getCookies()) {
                        if ("refreshToken".equals(c.getName()) && c.getValue() != null && !c.getValue().isBlank()) {
                            refreshToken = c.getValue();
                            break;
                        }
                    }
                }
            }

            if (refreshToken == null || refreshToken.trim().isEmpty()) {
                return ResponseEntity.status(401).body(new AuthFailureResponse("INVALID_REFRESH_TOKEN"));
            }

            Optional<RefreshToken> optionalToken = refreshTokenService.validateRefreshToken(refreshToken);
            if (optionalToken.isEmpty()) {
                return ResponseEntity.status(401).body(new AuthFailureResponse("INVALID_REFRESH_TOKEN"));
            }

            RefreshToken rt = optionalToken.get();

            Optional<User> userOpt = userRepository.findById(rt.getUserId());
            if (userOpt.isEmpty()) {
                refreshTokenService.revoke(rt, "user_not_found");
                return ResponseEntity.status(401).body(new AuthFailureResponse("USER_NOT_FOUND"));
            }

            User user = userOpt.get();

            if (failedLoginService.isLocked(user.getUserId()) || failedLoginService.isUsernameOrEmailLockedOrDisabled(user.getUsername(), user.getEmail())) {
                refreshTokenService.revoke(rt, "account_locked");
                return ResponseEntity.status(423).body(new AuthFailureResponse("ACCOUNT_LOCKED_OR_DISABLED"));
            }

            String newAccessToken = jwtTokenService.issueAccessTokenForUser(user.getUsername(), user.getUserId().toString());

            Claims claims = jwtUtil.parseClaims(newAccessToken);
            String newJti = claims.getId();

            String ip = request.getRemoteAddr();
            String ua = request.getHeader("User-Agent");
            String newRefreshToken = refreshTokenService.rotate(rt, UUID.fromString(newJti), ip, ua);

            outboxService.publish("lab.audit.events", Map.of(
                    "event", "TOKEN_REFRESHED",
                    "user_id", user.getUserId().toString(),
                    "username", user.getUsername()
            ));

            Map<String, String> response = new HashMap<>();
            response.put("accessToken", newAccessToken);
            response.put("token", newAccessToken);
            response.put("refreshToken", newRefreshToken);

            return ResponseEntity.ok(response);

        } catch (ExpiredJwtException e) {
            return ResponseEntity.status(401).body(new AuthFailureResponse("TOKEN_EXPIRED"));
        } catch (Exception e) {
            return ResponseEntity.status(500).body(new AuthFailureResponse("GENERAL_ERROR"));
        }
    }

    @PostMapping("/logout")
    public ResponseEntity<?> logout(HttpServletRequest request) {
        String header = request.getHeader("Authorization");
        if (header != null && header.startsWith("Bearer ")) {
            String token = header.substring(7);
            try {
                Claims claims = jwtUtil.parseClaims(token);
                String jti = claims.getId();
                String sub = claims.getSubject();
                if (jti != null) {
                    long ttl = jwtUtil.getAccessTokenTtlSeconds();
                    jwtBlacklistService.blacklistToken(jti, ttl);
                }
                outboxService.publish("lab.audit.events", Map.of("event","LOGOUT", "username", sub, "jti", jti));
            } catch (Exception ex) {
                outboxService.publish("lab.audit.events", Map.of("event","LOGOUT_INVALID_TOKEN"));
                return ResponseEntity.ok().build();
            }
        } else {
            outboxService.publish("lab.audit.events", Map.of("event","LOGOUT_NO_TOKEN"));
        }
        return ResponseEntity.ok().build();
    }
}
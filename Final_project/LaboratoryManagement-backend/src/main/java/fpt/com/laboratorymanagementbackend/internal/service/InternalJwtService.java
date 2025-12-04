package fpt.com.laboratorymanagementbackend.internal.service;

import fpt.com.laboratorymanagementbackend.internal.dto.InternalJwtVerifyRequest;
import fpt.com.laboratorymanagementbackend.internal.dto.InternalJwtVerifyResponse;
import fpt.com.laboratorymanagementbackend.security.jwt.JwtUtil;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.ExpiredJwtException;
import io.jsonwebtoken.MalformedJwtException;
import io.jsonwebtoken.security.SignatureException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.List;

@Slf4j
@Service
@RequiredArgsConstructor
public class InternalJwtService {

    private final JwtUtil jwtUtil;

    public InternalJwtVerifyResponse verifyToken(InternalJwtVerifyRequest request) {
        String token = request.getToken();

        if (token == null || token.isBlank()) {
            log.warn("Received empty token for verification");
            return InternalJwtVerifyResponse.builder()
                    .valid(false)
                    .errorMessage("Token is empty")
                    .build();
        }

        try {
            Claims claims = jwtUtil.parseClaims(token);

            String userId = claims.getId();
            String username = claims.getSubject();

            @SuppressWarnings("unchecked")
            List<String> authorities = claims.get("authorities", List.class);
            if (authorities == null) {
                authorities = List.of();
            }

            log.info("JWT verified successfully for user: {} (userId: {})", username, userId);

            return InternalJwtVerifyResponse.builder()
                    .valid(true)
                    .userId(userId)
                    .username(username)
                    .privileges(authorities)
                    .build();

        } catch (ExpiredJwtException e) {
            log.warn("JWT token expired: {}", e.getMessage());
            return InternalJwtVerifyResponse.builder()
                    .valid(false)
                    .errorMessage("Token expired")
                    .build();

        } catch (SignatureException e) {
            log.warn("JWT signature invalid: {}", e.getMessage());
            return InternalJwtVerifyResponse.builder()
                    .valid(false)
                    .errorMessage("Invalid token signature")
                    .build();

        } catch (MalformedJwtException e) {
            log.warn("JWT malformed: {}", e.getMessage());
            return InternalJwtVerifyResponse.builder()
                    .valid(false)
                    .errorMessage("Malformed token")
                    .build();

        } catch (Exception e) {
            log.error("Error verifying JWT: {}", e.getMessage(), e);
            return InternalJwtVerifyResponse.builder()
                    .valid(false)
                    .errorMessage("Token verification failed: " + e.getMessage())
                    .build();
        }
    }

}
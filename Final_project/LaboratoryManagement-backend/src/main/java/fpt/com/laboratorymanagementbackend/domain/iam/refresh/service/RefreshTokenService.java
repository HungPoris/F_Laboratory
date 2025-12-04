package fpt.com.laboratorymanagementbackend.domain.iam.refresh.service;

import fpt.com.laboratorymanagementbackend.domain.iam.refresh.entity.RefreshToken;
import fpt.com.laboratorymanagementbackend.domain.iam.refresh.repository.RefreshTokenRepository;
import fpt.com.laboratorymanagementbackend.common.util.TokenUtil;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.beans.factory.annotation.Value;
import java.time.OffsetDateTime;
import java.time.temporal.ChronoUnit;
import java.util.UUID;
import java.util.Optional;
import java.util.List;

@Service
public class RefreshTokenService {

    private static final Logger log = LoggerFactory.getLogger(RefreshTokenService.class);

    private final RefreshTokenRepository repo;

    @Value("${jwt.refresh.days:30}")
    private int refreshDays;

    @Value("${jwt.refresh.inactivity.minutes:15}")
    private int inactivityMinutes;

    public RefreshTokenService(RefreshTokenRepository repo) {
        this.repo = repo;
    }

    @Transactional
    public String createRefreshToken(UUID userId, String accessJti, String ip, String ua) {
        if (userId == null) {
            throw new IllegalArgumentException("userId cannot be null");
        }

        String token = TokenUtil.generateToken(48);
        String hash = TokenUtil.sha256Hex(token);

        RefreshToken rt = RefreshToken.builder()
                .tokenId(UUID.randomUUID())
                .userId(userId)
                .tokenHash(hash)
                .tokenFamilyId(UUID.randomUUID())
                .accessTokenJti(accessJti)
                .ipAddress(ip != null ? ip : "unknown")
                .userAgent(ua != null ? ua : "unknown")
                .isActive(true)
                .isRevoked(false)
                .createdAt(OffsetDateTime.now())
                .expiresAt(OffsetDateTime.now().plus(refreshDays, ChronoUnit.DAYS))
                .lastUsedAt(OffsetDateTime.now())
                .build();

        repo.save(rt);

        return token;
    }

    @Transactional
    public Optional<RefreshToken> validateRefreshToken(String token) {
        if (token == null || token.trim().isEmpty()) {
            return Optional.empty();
        }

        String hash = TokenUtil.sha256Hex(token);
        Optional<RefreshToken> or = repo.findByTokenHashAndIsActiveTrueAndIsRevokedFalse(hash);

        if (or.isEmpty()) {
            log.warn("Validation failed: token not found or inactive");
            return Optional.empty();
        }

        RefreshToken rt = or.get();

        if (rt.getExpiresAt() == null) {
            log.warn("Validation failed: token has no expiration date");
            return Optional.empty();
        }

        if (rt.getExpiresAt().isBefore(OffsetDateTime.now())) {
            log.warn("Validation failed: token expired at {}", rt.getExpiresAt());
            return Optional.empty();
        }

        OffsetDateTime now = OffsetDateTime.now();
        OffsetDateTime lastUsed = rt.getLastUsedAt();
        if (lastUsed != null && lastUsed.isBefore(now.minusMinutes(inactivityMinutes))) {
            log.info("Validation failed: token inactive since {}", lastUsed);
            return Optional.empty();
        }

        rt.setLastUsedAt(now);
        repo.save(rt);

        return Optional.of(rt);
    }

    @Transactional
    public String rotate(RefreshToken old, UUID newAccessJti, String ip, String ua) {
        if (old == null) {
            throw new IllegalArgumentException("old RefreshToken cannot be null");
        }
        if (newAccessJti == null) {
            throw new IllegalArgumentException("newAccessJti cannot be null");
        }

        old.setIsRevoked(true);
        old.setIsActive(false);
        old.setRevokedAt(OffsetDateTime.now());
        old.setRevokedReason("rotated");
        repo.save(old);

        String token = TokenUtil.generateToken(48);
        String hash = TokenUtil.sha256Hex(token);

        RefreshToken rt = RefreshToken.builder()
                .tokenId(UUID.randomUUID())
                .userId(old.getUserId())
                .tokenHash(hash)
                .tokenFamilyId(old.getTokenFamilyId())
                .accessTokenJti(newAccessJti.toString())
                .ipAddress(ip != null ? ip : old.getIpAddress())
                .userAgent(ua != null ? ua : old.getUserAgent())
                .isActive(true)
                .isRevoked(false)
                .createdAt(OffsetDateTime.now())
                .expiresAt(OffsetDateTime.now().plus(refreshDays, ChronoUnit.DAYS))
                .lastUsedAt(OffsetDateTime.now())
                .build();

        repo.save(rt);

        return token;
    }

    @Transactional
    public void revoke(RefreshToken token, String reason) {
        if (token == null) {
            return;
        }

        token.setIsRevoked(true);
        token.setIsActive(false);
        token.setRevokedAt(OffsetDateTime.now());
        token.setRevokedReason(reason != null ? reason : "manual_revoke");

        repo.save(token);
    }

    @Transactional
    public void revokeAllByUser(UUID userId) {
        if (userId == null) {
            return;
        }

        List<RefreshToken> tokens = repo.findByUserIdAndIsActiveTrueAndIsRevokedFalseAndExpiresAtAfter(
                userId,
                OffsetDateTime.now()
        );

        for (RefreshToken token : tokens) {
            token.setIsRevoked(true);
            token.setIsActive(false);
            token.setRevokedAt(OffsetDateTime.now());
            token.setRevokedReason("revoke_all_sessions");
            repo.save(token);
        }

        log.info("Revoked {} refresh tokens for user: {}", tokens.size(), userId);
    }

    @Transactional
    public int cleanupExpired() {
        OffsetDateTime cutoff = OffsetDateTime.now();
        int revoked = repo.revokeExpired(cutoff);
        log.info("Revoked {} expired tokens", revoked);
        return revoked;
    }

    @Transactional
    public int deleteExpired(int daysOld) {
        OffsetDateTime cutoff = OffsetDateTime.now().minusDays(daysOld);
        int deleted = repo.deleteExpired(cutoff);
        log.info("Deleted {} expired tokens older than {} days", deleted, daysOld);
        return deleted;
    }
}

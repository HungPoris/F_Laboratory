package fpt.com.laboratorymanagementbackend.domain.iam.auth.service;

import org.springframework.stereotype.Service;
import fpt.com.laboratorymanagementbackend.common.service.RedisRevocationService;
import fpt.com.laboratorymanagementbackend.domain.iam.refresh.repository.RefreshTokenRepository;
import java.time.OffsetDateTime;
import java.util.UUID;
import fpt.com.laboratorymanagementbackend.domain.iam.refresh.entity.RefreshToken;
import org.springframework.transaction.annotation.Transactional;

@Service
public class RefreshRevocationAdapter {
    private final RedisRevocationService redisRevocationService;
    private final RefreshTokenRepository refreshRepo;
    public RefreshRevocationAdapter(RedisRevocationService redisRevocationService, RefreshTokenRepository refreshRepo) {
        this.redisRevocationService = redisRevocationService;
        this.refreshRepo = refreshRepo;
    }
    @Transactional
    public void revokeByTokenId(UUID tokenId) {
        refreshRepo.findById(tokenId).ifPresent(rt -> {
            rt.setIsRevoked(true);
            rt.setIsActive(false);
            rt.setRevokedAt(OffsetDateTime.now());
            refreshRepo.save(rt);
            String jti = rt.getAccessTokenJti();
            if (jti != null) {
                long ttl = rt.getExpiresAt() != null ? java.time.Duration.between(OffsetDateTime.now(), rt.getExpiresAt()).getSeconds() : 0;
                if (ttl > 0) redisRevocationService.blacklistJti(jti, ttl);
            }
        });
    }
}

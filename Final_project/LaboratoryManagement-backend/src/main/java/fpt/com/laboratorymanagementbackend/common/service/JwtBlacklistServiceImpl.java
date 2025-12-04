package fpt.com.laboratorymanagementbackend.common.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.time.Instant;
import java.util.Set;
import java.util.stream.Collectors;

@Service
public class JwtBlacklistServiceImpl implements JwtBlacklistService {

    private final StringRedisTemplate redis;
    private final String blacklistPrefix;
    private final String userTokensPrefix;
    private final long defaultBlacklistTtlSeconds;

    public JwtBlacklistServiceImpl(StringRedisTemplate redis,
                                   @Value("${app.jwt.blacklist.prefix:iam:jwt:blacklist:}") String blacklistPrefix,
                                   @Value("${app.jwt.user.tokens.prefix:iam:jwt:user:}") String userTokensPrefix,
                                   @Value("${app.jwt.blacklist.ttl-seconds:900}") long defaultBlacklistTtlSeconds) {
        this.redis = redis;
        this.blacklistPrefix = blacklistPrefix.endsWith(":") ? blacklistPrefix : blacklistPrefix + ":";
        this.userTokensPrefix = userTokensPrefix.endsWith(":") ? userTokensPrefix : userTokensPrefix + ":";
        this.defaultBlacklistTtlSeconds = defaultBlacklistTtlSeconds;
    }

    private String userTokensKey(String userId) {
        return userTokensPrefix + userId + ":tokens";
    }

    private String userRevokedKey(String userId) {
        return userTokensPrefix + userId + ":revoked_at";
    }

    @Override
    public void blacklistToken(String jti, long ttlSeconds) {
        if (jti == null || jti.isBlank()) return;
        String key = blacklistPrefix + jti;
        redis.opsForValue().set(key, "1", Duration.ofSeconds(ttlSeconds > 0 ? ttlSeconds : defaultBlacklistTtlSeconds));
    }

    @Override
    public boolean isBlacklisted(String jti) {
        if (jti == null || jti.isBlank()) return false;
        String key = blacklistPrefix + jti;
        return Boolean.TRUE.equals(redis.hasKey(key));
    }

    @Override
    public void recordTokenForUser(String userId, String jti, long ttlSeconds) {
        if (userId == null || userId.isBlank() || jti == null || jti.isBlank()) return;
        String key = userTokensKey(userId);
        redis.opsForSet().add(key, jti);
        redis.expire(key, Duration.ofSeconds(ttlSeconds > 0 ? ttlSeconds : defaultBlacklistTtlSeconds));
    }

    @Override
    public void blacklistAllTokensForUser(String userId) {
        if (userId == null || userId.isBlank()) return;
        String tokensKey = userTokensKey(userId);
        Set<String> members = redis.opsForSet().members(tokensKey);
        if (members != null && !members.isEmpty()) {
            long ttl = defaultBlacklistTtlSeconds;
            Set<String> copy = members.stream().collect(Collectors.toSet());
            for (String jti : copy) {
                blacklistToken(jti, ttl);
            }
        }
        String nowEpochSec = String.valueOf(Instant.now().getEpochSecond());
        long ttl = Math.max(defaultBlacklistTtlSeconds * 10, defaultBlacklistTtlSeconds);
        redis.opsForValue().set(userRevokedKey(userId), nowEpochSec, Duration.ofSeconds(ttl));
        redis.delete(tokensKey);
    }
}

package fpt.com.laboratorymanagementbackend.common.service;

import org.springframework.stereotype.Service;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.beans.factory.annotation.Value;
import java.time.Duration;

@Service
public class RedisRevocationService {
    private final StringRedisTemplate redis;
    private final String prefix;

    public RedisRevocationService(StringRedisTemplate redis,
                                  @Value("${app.jwt.blacklist.prefix:iam:jwt:blacklist:}") String prefix) {
        this.redis = redis;
        this.prefix = prefix;
    }

    public void blacklistJti(String jti, long ttlSeconds) {
        if (jti == null || ttlSeconds <= 0) return;
        String key = prefix + jti;
        redis.opsForValue().set(key, "1", Duration.ofSeconds(ttlSeconds));
    }
}

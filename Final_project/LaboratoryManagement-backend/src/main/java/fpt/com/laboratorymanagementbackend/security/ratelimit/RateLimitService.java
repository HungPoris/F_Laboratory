package fpt.com.laboratorymanagementbackend.security.ratelimit;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.util.concurrent.TimeUnit;

@Service
public class RateLimitService {
    private static final Logger log = LoggerFactory.getLogger(RateLimitService.class);
    private final StringRedisTemplate redis;

    public RateLimitService(StringRedisTemplate redis) {
        this.redis = redis;
    }

    public boolean isAllowed(String key, int maxRequests, int windowSeconds) {
        try {
            Long count = redis.opsForValue().increment(key, 1);
            if (count == null) return true;
            if (count == 1L) {
                redis.expire(key, Duration.ofSeconds(windowSeconds).toMillis(), TimeUnit.MILLISECONDS);
            }
            return count <= maxRequests;
        } catch (Exception e) {
            log.warn("RateLimit degraded, Redis unavailable", e);
            return true;
        }
    }

    public void reset(String key) {
        try {
            redis.delete(key);
        } catch (Exception ignored) {
        }
    }
}

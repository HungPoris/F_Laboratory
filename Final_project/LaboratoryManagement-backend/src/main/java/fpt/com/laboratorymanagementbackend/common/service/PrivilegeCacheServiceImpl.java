package fpt.com.laboratorymanagementbackend.common.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

import java.time.Duration;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.Set;

@Service
public class PrivilegeCacheServiceImpl implements PrivilegeCacheService {

    private static final Logger log = LoggerFactory.getLogger(PrivilegeCacheServiceImpl.class);

    private final StringRedisTemplate redis;
    private final ObjectMapper objectMapper;
    private final long ttlSeconds;
    private final String redisPrefix;
    private final String namespace;

    public PrivilegeCacheServiceImpl(StringRedisTemplate redis,
                                     ObjectMapper objectMapper,
                                     @Value("${app.cache.ttl.permission-seconds:900}") long ttlSeconds,
                                     @Value("${app.redis.key-prefix:}") String redisPrefix,
                                     @Value("${app.cache.namespace:iam:user}") String namespace) {
        this.redis = redis;
        this.objectMapper = objectMapper;
        this.ttlSeconds = ttlSeconds;
        this.redisPrefix = (redisPrefix == null || redisPrefix.isBlank()) ? "" : redisPrefix.trim();
        this.namespace = (namespace == null || namespace.isBlank()) ? "iam:user" : namespace.trim();
    }

    @Override
    public void putPrivileges(String userId, Set<String> privileges) {
        if (userId == null || userId.isBlank() || privileges == null || privileges.isEmpty()) {
            return;
        }
        if (redis == null || objectMapper == null) {
            //log.warn("PrivilegeCacheService: redis or objectMapper is not available; skipping cache put for userId={}", userId);
            return;
        }

        try {
            String key = buildKey(userId);
            String value = objectMapper.writeValueAsString(privileges);
            if (ttlSeconds > 0) {
                redis.opsForValue().set(key, value, Duration.ofSeconds(ttlSeconds));
            } else {
                redis.opsForValue().set(key, value);
            }
        } catch (Exception ex) {
            //log.warn("PrivilegeCacheService: failed to put privileges into redis for userId={}, err={}", userId, ex.getMessage());
        }
    }

    @Override
    public Set<String> getPrivileges(String userId) {
        if (userId == null || userId.isBlank()) return Collections.emptySet();
        if (redis == null || objectMapper == null) {
            //log.debug("PrivilegeCacheService: redis or objectMapper not available; returning empty privileges for userId={}", userId);
            return Collections.emptySet();
        }

        try {
            String v = redis.opsForValue().get(buildKey(userId));
            if (v == null || v.isBlank()) return Collections.emptySet();
            Set<String> set = objectMapper.readValue(v, new TypeReference<LinkedHashSet<String>>() {});
            return set == null ? Collections.emptySet() : set;
        } catch (Exception ex) {
            //log.warn("PrivilegeCacheService: failed to read privileges from redis for userId={}, err={}", userId, ex.getMessage());
            return Collections.emptySet();
        }
    }

    @Override
    public void evict(String userId) {
        if (userId == null || userId.isBlank()) return;
        if (redis == null) {
            //log.warn("PrivilegeCacheService: redis not available; cannot evict privileges for userId={}", userId);
            return;
        }
        try {
            redis.delete(buildKey(userId));
        } catch (Exception ex) {
            //log.warn("PrivilegeCacheService: failed to evict cache for userId={}, err={}", userId, ex.getMessage());
        }
    }

    private String buildKey(String userId) {
        String p = redisPrefix.isEmpty() ? "" : (redisPrefix.endsWith(":") ? redisPrefix : (redisPrefix + ":"));
        return p + namespace + ":" + userId + ":privileges";
    }
}

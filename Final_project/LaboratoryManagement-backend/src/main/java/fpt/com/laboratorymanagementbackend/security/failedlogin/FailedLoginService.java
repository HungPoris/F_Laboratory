package fpt.com.laboratorymanagementbackend.security.failedlogin;

import fpt.com.laboratorymanagementbackend.common.service.OutboxService;
import fpt.com.laboratorymanagementbackend.domain.iam.user.entity.User;
import fpt.com.laboratorymanagementbackend.domain.iam.user.repository.UserRepository;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.Optional;
import java.util.UUID;

@Service
public class FailedLoginService {

    private final StringRedisTemplate redis;
    private final UserRepository userRepository;
    private final OutboxService outboxService;
    private final int threshold;
    private final long failTtlSeconds;
    private final String failPrefix;
    private final String userLockPrefix;

    public FailedLoginService(StringRedisTemplate redis,
                              UserRepository userRepository,
                              OutboxService outboxService,
                              @Value("${security.lockout.max-attempts:5}") int threshold,
                              @Value("${app.otp.fail.ttl-seconds:600}") long failTtlSeconds,
                              @Value("${app.otp.fail.prefix:iam:login:failed:}") String failPrefix,
                              @Value("${app.redis.lock.prefix:iam:user:}") String userLockPrefix) {
        this.redis = redis;
        this.userRepository = userRepository;
        this.outboxService = outboxService;
        this.threshold = threshold;
        this.failTtlSeconds = failTtlSeconds;
        this.failPrefix = failPrefix.endsWith(":") ? failPrefix : failPrefix + ":";
        this.userLockPrefix = userLockPrefix.endsWith(":") ? userLockPrefix : userLockPrefix + ":";
    }

    public int incrementFailedAttempts(String username) {
        if (username == null) return 0;
        String key = failPrefix + username.toLowerCase();
        Long v = redis.opsForValue().increment(key);
        if (v != null && v == 1L) {
            redis.expire(key, failTtlSeconds, java.util.concurrent.TimeUnit.SECONDS);
        }
        return v == null ? 0 : v.intValue();
    }


    public void clearFailedAttempts(String username) {
        if (username == null) return;
        String key = failPrefix + username.toLowerCase();
        redis.delete(key);
    }

    public boolean isLockedInRedis(UUID userId) {
        if (userId == null) return false;
        String key = userLockPrefix + userId + ":locked";
        return Boolean.TRUE.equals(redis.hasKey(key));
    }

    @Transactional
    public void applyAdminLock(UUID userId, String username) {
        if (userId == null) return;
        userRepository.findById(userId).ifPresent(u -> {
            u.setIsLocked(true);
            u.setLockedAt(OffsetDateTime.now());
            u.setLockedUntil(null);
            u.setLockedReason("Temporarily locked due to " + threshold + " incorrect password attempts");
            userRepository.save(u);
            String key = userLockPrefix + userId + ":locked";
            redis.opsForValue().set(key, "1");
            clearFailedAttempts(username);
            outboxService.publish("lab.audit.events", java.util.Map.of(
                    "event", "USER_LOCKED",
                    "user_id", userId.toString(),
                    "mode", "ADMIN_ONLY",
                    "reason", "Temporarily locked due to " + threshold + " incorrect password attempts"
            ));
        });
    }

    public boolean checkAndHandleFailure(String username) {
        if (username == null) return false;
        Optional<User> maybe = userRepository.findByUsernameIgnoreCase(username);
        UUID uid = maybe.map(User::getUserId).orElse(null);
        int count = incrementFailedAttempts(username);
        if (uid != null) {
            outboxService.publish("lab.audit.events", java.util.Map.of(
                    "event", "LOGIN_FAILED",
                    "user_id", uid.toString(),
                    "attempts", count
            ));
        } else {
            outboxService.publish("lab.audit.events", java.util.Map.of(
                    "event", "LOGIN_FAILED_UNKNOWN",
                    "username", username
            ));
        }
        if (count >= threshold && uid != null) {
            applyAdminLock(uid, username);
            return true;
        }
        return false;
    }

    public boolean isLocked(UUID userId) {
        if (userId == null) return false;
        Optional<User> u = userRepository.findById(userId);
        if (u.isEmpty()) return false;
        User user = u.get();
        if (Boolean.TRUE.equals(user.getIsLocked())) return true;
        return isLockedInRedis(userId);
    }

    public boolean isUsernameOrEmailLockedOrDisabled(String username, String email) {
        if (username != null) {
            Optional<User> byUsername = userRepository.findByUsernameIgnoreCase(username);
            if (byUsername.isPresent()) {
                User u = byUsername.get();
                if (Boolean.FALSE.equals(u.getIsActive()) || Boolean.TRUE.equals(u.getIsLocked())) return true;
            }
        }
        if (email != null) {
            Optional<User> byEmail = userRepository.findByEmailIgnoreCase(email);
            if (byEmail.isPresent()) {
                User u = byEmail.get();
                if (Boolean.FALSE.equals(u.getIsActive()) || Boolean.TRUE.equals(u.getIsLocked())) return true;
            }
        }
        return false;
    }

    @Transactional
    public void clearLock(UUID userId) {
        if (userId == null) return;
        userRepository.findById(userId).ifPresent(u -> {
            u.setIsLocked(false);
            u.setLockedAt(null);
            u.setLockedUntil(null);
            u.setFailedLoginAttempts(0);
            u.setLockedReason(null);
            userRepository.save(u);
            String key = userLockPrefix + userId + ":locked";
            redis.delete(key);
            clearFailedAttempts(u.getUsername());
            outboxService.publish("lab.audit.events", java.util.Map.of(
                    "event", "USER_UNLOCKED",
                    "user_id", userId.toString()
            ));
        });
    }
}

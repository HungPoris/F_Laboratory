package fpt.com.laboratorymanagementbackend.domain.iam.user.service;

import org.springframework.stereotype.Service;
import fpt.com.laboratorymanagementbackend.domain.iam.user.repository.UserRepository;
import fpt.com.laboratorymanagementbackend.common.service.OutboxService;
import org.springframework.transaction.annotation.Transactional;
import java.time.OffsetDateTime;
import java.util.UUID;

@Service
public class LockoutService {
    private final UserRepository userRepository;
    private final OutboxService outboxService;

    private final int threshold = 5;

    public LockoutService(UserRepository userRepository, OutboxService outboxService) {
        this.userRepository = userRepository;
        this.outboxService = outboxService;
    }

    @Transactional
    public void registerFailedAttempt(UUID userId) {
        userRepository.findById(userId).ifPresent(u -> {
            Integer attempts = u.getFailedLoginAttempts() == null ? 0 : u.getFailedLoginAttempts();
            attempts = attempts + 1;
            u.setFailedLoginAttempts(attempts);
            u.setLastFailedLoginAt(OffsetDateTime.now());
            if (attempts >= threshold) {
                u.setIsLocked(true);
                u.setLockedAt(OffsetDateTime.now());
                u.setLockedUntil(null);
                u.setLockedReason("Temporarily locked due to " + threshold + " incorrect password attempts");
                userRepository.save(u);
                outboxService.publish("lab.audit.events", java.util.Map.of(
                        "event","USER_LOCKED",
                        "user_id", userId.toString(),
                        "attempts", attempts,
                        "mode","ADMIN_ONLY",
                        "reason","Temporarily locked due to " + threshold + " incorrect password attempts"
                ));
            } else {
                userRepository.save(u);
                outboxService.publish("lab.audit.events", java.util.Map.of(
                        "event","LOGIN_FAILED",
                        "user_id", userId.toString(),
                        "attempts", attempts
                ));
            }
        });
    }

    @Transactional
    public void resetFailedAttempts(UUID userId) {
        userRepository.findById(userId).ifPresent(u -> {
            u.setFailedLoginAttempts(0);
            userRepository.save(u);
        });
    }
}

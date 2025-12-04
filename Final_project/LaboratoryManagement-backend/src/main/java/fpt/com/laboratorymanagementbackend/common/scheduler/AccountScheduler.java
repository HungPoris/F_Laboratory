package fpt.com.laboratorymanagementbackend.common.scheduler;

import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import fpt.com.laboratorymanagementbackend.domain.iam.user.repository.UserRepository;
import fpt.com.laboratorymanagementbackend.common.service.OutboxService;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;
import org.springframework.beans.factory.annotation.Value;

@Component
public class AccountScheduler {
    private final UserRepository userRepository;
    private final OutboxService outboxService;
    @Value("${app.account.inactive-days:90}")
    private int inactiveDays;
    public AccountScheduler(UserRepository userRepository, OutboxService outboxService) {
        this.userRepository = userRepository;
        this.outboxService = outboxService;
    }
    @Scheduled(cron = "${security.lockout.daily-reset-cron:0 0 23 * * *}")
    public void resetDailyFailedAttempts() {
        userRepository.findAll().stream().filter(u -> u.getFailedLoginAttempts() != null && u.getFailedLoginAttempts() > 0 && (u.getIsLocked() == null || !u.getIsLocked())).forEach(u -> {
            u.setFailedLoginAttempts(0);
            userRepository.save(u);
        });
    }
    @Scheduled(cron = "${scheduler.tokens.cleanup-daily-cron:0 0 3 * * *}")
    public void disableInactiveAccounts() {
        OffsetDateTime threshold = OffsetDateTime.now(ZoneOffset.UTC).minusDays(inactiveDays);
        List<?> list = userRepository.findActiveButInactiveSince(threshold);
        for (Object o : list) {
            fpt.com.laboratorymanagementbackend.domain.iam.user.entity.User u = (fpt.com.laboratorymanagementbackend.domain.iam.user.entity.User) o;
            u.setIsActive(false);
            userRepository.save(u);
            outboxService.publish("lab.audit.events", java.util.Map.of("event","USER_DISABLED_INACTIVE","user_id", u.getUserId().toString()));
        }
    }
}

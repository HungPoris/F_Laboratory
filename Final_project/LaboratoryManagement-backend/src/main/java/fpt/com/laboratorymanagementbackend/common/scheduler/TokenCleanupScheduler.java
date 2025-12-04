package fpt.com.laboratorymanagementbackend.common.scheduler;


import org.springframework.stereotype.Component;
import org.springframework.scheduling.annotation.Scheduled;
import fpt.com.laboratorymanagementbackend.domain.iam.refresh.repository.RefreshTokenRepository;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Counter;
import org.springframework.beans.factory.annotation.Value;

@Component
public class TokenCleanupScheduler {
    private final RefreshTokenRepository refreshRepo;
    private final Counter revokeCounter;
    private final Counter deleteCounter;
    private final long auditTtlDays;

    public TokenCleanupScheduler(RefreshTokenRepository refreshRepo, MeterRegistry meterRegistry, @Value("${app.audit.ttl-days:180}") long auditTtlDays) {
        this.refreshRepo = refreshRepo;
        this.revokeCounter = meterRegistry.counter("tokens.revoke.count");
        this.deleteCounter = meterRegistry.counter("tokens.delete.count");
        this.auditTtlDays = auditTtlDays;
    }

    @Scheduled(cron = "${scheduler.tokens.cleanup-hourly-cron:0 0 * * * *}")
    public void hourlyCleanup() {
        OffsetDateTime now = OffsetDateTime.now(ZoneOffset.UTC);
        int revoked = refreshRepo.revokeExpired(now);
        revokeCounter.increment(revoked);
    }

    @Scheduled(cron = "${scheduler.tokens.cleanup-daily-cron:0 0 3 * * *}")
    public void dailyCleanup() {
        OffsetDateTime cutoff = OffsetDateTime.now(ZoneOffset.UTC).minusDays(auditTtlDays);
        int deleted = refreshRepo.deleteExpired(cutoff);
        deleteCounter.increment(deleted);
    }
}


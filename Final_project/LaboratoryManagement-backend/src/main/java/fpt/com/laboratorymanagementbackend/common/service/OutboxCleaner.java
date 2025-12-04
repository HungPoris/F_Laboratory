package fpt.com.laboratorymanagementbackend.common.service;

import fpt.com.laboratorymanagementbackend.common.outbox.repository.OutboxEventRepository;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;

@Component
public class OutboxCleaner {
    private final OutboxEventRepository repo;
    public OutboxCleaner(OutboxEventRepository repo) { this.repo = repo; }

    @Scheduled(cron = "${outbox.purge.cron:0 0 4 * * *}")
    @Transactional
    public void purgeOldSentEvents() {
        OffsetDateTime cutoff = OffsetDateTime.now(ZoneOffset.UTC).minusDays(30);
        repo.purgeSentOlderThan(cutoff);
    }
}

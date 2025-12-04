package fpt.com.laboratorymanagementbackend.common.service;

import fpt.com.laboratorymanagementbackend.common.outbox.entity.OutboxEvent;
import fpt.com.laboratorymanagementbackend.common.outbox.entity.OutboxMessage;
import fpt.com.laboratorymanagementbackend.common.outbox.repository.OutboxEventRepository;
import fpt.com.laboratorymanagementbackend.common.audit.service.AuditService;
import fpt.com.laboratorymanagementbackend.common.outbox.repository.OutboxMessageRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

@Service
public class OutboxPublisher {
    private final OutboxMessageRepository messageRepo;
    private final OutboxEventRepository eventRepo;
    private final RabbitTemplate rabbit;
    private final AuditService auditService;
    private static final Logger log = LoggerFactory.getLogger(OutboxPublisher.class);

    @Value("${outbox.publisher.max-attempts:3}")
    private int maxAttempts;

    @Value("${outbox.publisher.batch-size:50}")
    private int batchSize;

    public OutboxPublisher(OutboxMessageRepository messageRepo, OutboxEventRepository eventRepo, RabbitTemplate rabbit, AuditService auditService) {
        this.messageRepo = messageRepo;
        this.eventRepo = eventRepo;
        this.rabbit = rabbit;
        this.auditService = auditService;
    }

    @Scheduled(fixedDelayString = "${outbox.publisher.delay-ms:5000}")
    public void publishPending() {
        List<OutboxMessage> list = fetchPendingTransactional();
        if (list == null || list.isEmpty()) return;
        int processed = 0;
        for (OutboxMessage m : list) {
            if (processed >= batchSize) break;
            boolean ok = false;
            for (int attempt = 1; attempt <= maxAttempts; attempt++) {
                try {
                    rabbit.convertAndSend(m.getExchange(), m.getRoutingKey(), m.getPayload());
                    try {
                        UUID outboxId = m.getId();
                        auditService.recordPublishedEvent(outboxId, m.getRoutingKey(), m.getPayload());
                    } catch (Exception ignored) {
                    }
                    markMessageSent(m);
                    ok = true;
                    processed++;
                    //log.info("Published outbox message {} -> {}/{}", m.getId(), m.getExchange(), m.getRoutingKey());
                    break;
                } catch (Exception ex) {
                    long backoff = 500L * (1L << (attempt - 1));
                    //log.warn("Failed publish outbox {} attempt {}/{}: {}", m.getId(), attempt, maxAttempts, ex.getMessage());
                    try {
                        TimeUnit.MILLISECONDS.sleep(backoff);
                    } catch (InterruptedException ie) {
                        Thread.currentThread().interrupt();
                        break;
                    }
                }
            }
            if (!ok) {
                //log.error("Giving up publishing outbox {} after {} attempts", m.getId(), maxAttempts);
            }
        }
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    protected void markMessageSent(OutboxMessage m) {
        messageRepo.findById(m.getId()).ifPresent(msg -> {
            msg.setStatus("SENT");
            msg.setPublishedAt(OffsetDateTime.now());
            msg.setAttempts((msg.getAttempts() == null ? 0 : msg.getAttempts()) + 1);
            messageRepo.save(msg);
            OutboxEvent ev = new OutboxEvent();
            ev.setEventId(UUID.randomUUID());
            ev.setTopic(m.getRoutingKey());
            ev.setPayload(m.getPayload());
            ev.setCreatedAt(OffsetDateTime.now());
            ev.setSent(true);
            ev.setSentAt(OffsetDateTime.now());
            eventRepo.save(ev);
        });
    }

    @Transactional(readOnly = true)
    protected List<OutboxMessage> fetchPendingTransactional() {
        return messageRepo.findPending();
    }
}

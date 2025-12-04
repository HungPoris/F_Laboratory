package fpt.com.laboratorymanagementbackend.common.service;

import fpt.com.laboratorymanagementbackend.common.outbox.entity.OutboxMessage;
import fpt.com.laboratorymanagementbackend.common.outbox.repository.OutboxMessageRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.UUID;

@Slf4j
@Service
@RequiredArgsConstructor
public class OutboxService {

    private final OutboxMessageRepository repo;
    private final ObjectMapper objectMapper;

    @Value("${notify.exchange.name:notify.exchange}")
    private String defaultExchange;

    @Transactional
    public boolean publish(String routingKey, Object payload) {
        return publishToExchange(defaultExchange, routingKey, payload);
    }

    @Transactional
    public boolean publishToExchange(String exchange, String routingKey, Object payload) {
        try {
            String ex = exchange == null || exchange.isBlank() ? defaultExchange : exchange;
            String rk = routingKey == null || routingKey.isBlank() ? "default" : routingKey;
            String json = objectMapper.writeValueAsString(payload);
            OutboxMessage m = new OutboxMessage();
            m.setId(UUID.randomUUID());
            m.setExchange(ex);
            m.setRoutingKey(rk);
            m.setPayload(json);
            m.setStatus("PENDING");
            m.setAttempts(0);
            m.setCreatedAt(OffsetDateTime.now());
            repo.save(m);
            return true;
        } catch (Exception ex) {
            log.warn("Outbox publish failed", ex);
            return false;
        }
    }
}

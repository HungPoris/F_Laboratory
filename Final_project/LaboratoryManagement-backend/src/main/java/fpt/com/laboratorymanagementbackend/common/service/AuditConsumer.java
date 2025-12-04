package fpt.com.laboratorymanagementbackend.common.service;

import org.springframework.stereotype.Component;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import fpt.com.laboratorymanagementbackend.common.audit.repository.AuditLogRepository;
import fpt.com.laboratorymanagementbackend.common.audit.model.AuditLog;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.core.type.TypeReference;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeParseException;
import java.util.Map;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

@Component
public class AuditConsumer {
    private final AuditLogRepository repo;
    private final ObjectMapper mapper;
    private static final Logger log = LoggerFactory.getLogger(AuditConsumer.class);

    public AuditConsumer(AuditLogRepository repo, ObjectMapper mapper) {
        this.repo = repo;
        this.mapper = mapper;
    }

    @RabbitListener(queues = "lab.audit.queue")
    public void handleAuditMessage(String message) {
        try {
            Map<String, Object> payload = mapper.readValue(message, new TypeReference<Map<String, Object>>() {});
            Object auditFlagObj = payload.get("audit_recorded");
            boolean auditRecorded = false;
            if (auditFlagObj instanceof Boolean) {
                auditRecorded = (Boolean) auditFlagObj;
            } else if (auditFlagObj instanceof String) {
                auditRecorded = Boolean.parseBoolean(((String) auditFlagObj).trim());
            }
            if (auditRecorded) {
                log.debug("Skipping audit insert because audit_recorded=true for payload: {}", safeKey(payload, "event_id"));
                return;
            }

            AuditLog al = new AuditLog();

            Object ev = payload.get("event");
            String eventName = ev == null ? "UNKNOWN" : ev.toString();
            al.setEvent(eventName);

            Object eid = firstNonNull(payload.get("event_id"), payload.get("eventId"), payload.get("id"));
            UUID eventId = tryParseUUID(eid);
            if (eventId != null) al.setEventId(eventId);

            if (eventId != null && repo.existsByEventId(eventId)) {
                log.debug("Audit record already exists for event {}", eventId);
                return;
            }

            al.setPayload(payload);

            OffsetDateTime createdAt = tryExtractTimestamp(payload, "createdAt", "timestamp", "time", "ts");
            if (createdAt == null) createdAt = OffsetDateTime.now(ZoneOffset.UTC);
            al.setCreatedAt(createdAt);

            UUID userId = tryParseUUID(payload.get("user_id"), payload.get("userId"), payload.get("uid"));
            if (userId != null) al.setUserId(userId);
            Object username = firstNonNull(payload.get("username"), payload.get("user_name"), payload.get("user"));
            if (username != null) al.setUsername(username.toString());

            UUID actorId = tryParseUUID(payload.get("actor_id"), payload.get("actorId"));
            if (actorId != null) al.setActorId(actorId);
            Object actorUsername = firstNonNull(payload.get("actor_username"), payload.get("actorUser"), payload.get("actor"));
            if (actorUsername != null) al.setActorUsername(actorUsername.toString());

            Object reqId = firstNonNull(payload.get("requestId"), payload.get("request_id"), payload.get("correlationId"), payload.get("correlation_id"));
            if (reqId != null) al.setRequestId(reqId.toString());

            Object source = payload.get("source");
            if (source != null) al.setSource(source.toString());

            Object clientIp = firstNonNull(payload.get("client_ip"), payload.get("clientIp"), payload.get("ip"));
            if (clientIp != null) al.setClientIp(clientIp.toString());

            Object ua = firstNonNull(payload.get("user_agent"), payload.get("userAgent"), payload.get("ua"));
            if (ua != null) al.setUserAgent(ua.toString());

            Object jti = firstNonNull(payload.get("token_jti"), payload.get("tokenJti"), payload.get("jti"));
            if (jti != null) al.setTokenJti(jti.toString());

            Object severity = payload.get("severity");
            if (severity != null) al.setSeverity(severity.toString());

            try {
                repo.save(al);
                log.info("Saved audit log event={} user={} actor={} at={}", al.getEvent(), al.getUsername(), al.getActorUsername(), al.getCreatedAt());
            } catch (Exception ex) {
                log.warn("Audit save failed (possible duplicate or transient): {}", ex.getMessage());
            }
        } catch (Exception ex) {
            log.error("Failed to process audit message: {}", ex.getMessage(), ex);
        }
    }

    private UUID tryParseUUID(Object... candidates) {
        if (candidates == null) return null;
        for (Object o : candidates) {
            if (o == null) continue;
            try {
                return UUID.fromString(o.toString());
            } catch (Exception ignored) {}
        }
        return null;
    }

    private OffsetDateTime tryExtractTimestamp(Map<String, Object> payload, String... keys) {
        if (payload == null) return null;
        for (String k : keys) {
            Object v = payload.get(k);
            if (v == null) continue;
            try {
                if (v instanceof Number) {
                    long epoch = ((Number) v).longValue();
                    if (String.valueOf(epoch).length() > 12) {
                        return OffsetDateTime.ofInstant(java.time.Instant.ofEpochMilli(epoch), ZoneOffset.UTC);
                    } else {
                        return OffsetDateTime.ofInstant(java.time.Instant.ofEpochSecond(epoch), ZoneOffset.UTC);
                    }
                }
                String s = v.toString();
                try {
                    return OffsetDateTime.parse(s);
                } catch (DateTimeParseException dtpe) {
                    try {
                        java.time.Instant inst = java.time.Instant.parse(s);
                        return OffsetDateTime.ofInstant(inst, ZoneOffset.UTC);
                    } catch (DateTimeParseException ignored) {}
                }
            } catch (Exception ignored) {}
        }
        return null;
    }

    private Object firstNonNull(Object... candidates) {
        if (candidates == null) return null;
        for (Object o : candidates) if (o != null) return o;
        return null;
    }

    private Object safeKey(Map<String, Object> m, String key) {
        try {
            return m == null ? null : m.get(key);
        } catch (Exception e) {
            return null;
        }
    }
}

package fpt.com.laboratorymanagementbackend.common.audit.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import fpt.com.laboratorymanagementbackend.common.audit.model.AuditLog;
import fpt.com.laboratorymanagementbackend.common.audit.repository.AuditLogRepository;
import fpt.com.laboratorymanagementbackend.common.audit.dto.AuditLogDto;
import fpt.com.laboratorymanagementbackend.common.util.TimeUtils;
import org.springframework.stereotype.Service;
import org.springframework.data.domain.Sort;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

@Service
public class AuditService {
    private final AuditLogRepository auditRepo;
    private final ObjectMapper mapper;
    public AuditService(AuditLogRepository auditRepo, ObjectMapper mapper) {
        this.auditRepo = auditRepo;
        this.mapper = mapper;
    }
    public void recordPublishedEvent(UUID eventId, String topic, String payloadJson) {
        if (eventId == null) return;
        if (auditRepo.existsByEventId(eventId)) return;
        AuditLog a = new AuditLog();
        a.setEventId(eventId);
        a.setEvent(topic);
        Map<String,Object> payloadMap;
        try {
            payloadMap = mapper.readValue(payloadJson, new TypeReference<Map<String,Object>>() {});
        } catch (Exception ex) {
            payloadMap = Map.of("raw", payloadJson);
        }
        a.setPayload(payloadMap);
        OffsetDateTime ts = tryExtractTimestamp(payloadMap, "createdAt", "timestamp", "time", "ts");
        if (ts == null) ts = OffsetDateTime.now(ZoneOffset.UTC);
        a.setCreatedAt(ts);

        UUID userId = tryParseUUID(payloadMap.get("user_id"), payloadMap.get("userId"), payloadMap.get("uid"));
        if (userId != null) a.setUserId(userId);
        Object username = firstNonNull(payloadMap.get("username"), payloadMap.get("user_name"), payloadMap.get("user"));
        if (username != null) a.setUsername(username.toString());

        try {
            auditRepo.save(a);
        } catch (Exception ignored) {
        }
    }

    public List<AuditLogDto> listAllDto() {
        List<AuditLog> items = auditRepo.findAll(Sort.by(Sort.Direction.DESC, "createdAt"));
        return items.stream().map(a -> {
            String id = a.getId();
            String userId = a.getUserId() != null ? a.getUserId().toString() : null;
            String actorId = a.getActorId() != null ? a.getActorId().toString() : null;
            String createdLocalIso = TimeUtils.toIsoWithZone(a.getCreatedAt());
            return new AuditLogDto(
                    id,
                    a.getEvent(),
                    userId,
                    a.getUsername(),
                    actorId,
                    a.getActorUsername(),
                    a.getRequestId(),
                    a.getSource(),
                    a.getClientIp(),
                    a.getUserAgent(),
                    a.getTokenJti(),
                    a.getSeverity(),
                    a.getPayload(),
                    a.getCreatedAt(),
                    createdLocalIso
            );
        }).collect(Collectors.toList());
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

    private OffsetDateTime tryExtractTimestamp(Map<String,Object> payload, String... keys) {
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
                } catch (Exception dtpe) {
                    try {
                        java.time.Instant inst = java.time.Instant.parse(s);
                        return OffsetDateTime.ofInstant(inst, ZoneOffset.UTC);
                    } catch (Exception ignored) {}
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
}

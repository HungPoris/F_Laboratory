package fpt.com.laboratorymanagementbackend.common.audit.model;

import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;
import org.springframework.data.annotation.Id;
import java.time.OffsetDateTime;
import java.util.Map;
import java.util.UUID;

@Document(collection = "audit_logs")
public class AuditLog {
    @Id
    private String id;

    @Indexed(unique = true)
    private UUID eventId;

    @Indexed
    private String event;

    @Indexed
    private UUID userId;

    private String username;

    @Indexed
    private UUID actorId;

    private String actorUsername;

    private String requestId;

    private String source;

    private String clientIp;

    private String userAgent;

    private String tokenJti;

    private String severity;

    private Map<String, Object> payload;

    @Indexed
    private OffsetDateTime createdAt;

    public AuditLog() {}

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }

    public UUID getEventId() { return eventId; }
    public void setEventId(UUID eventId) { this.eventId = eventId; }

    public String getEvent() { return event; }
    public void setEvent(String event) { this.event = event; }

    public UUID getUserId() { return userId; }
    public void setUserId(UUID userId) { this.userId = userId; }

    public String getUsername() { return username; }
    public void setUsername(String username) { this.username = username; }

    public UUID getActorId() { return actorId; }
    public void setActorId(UUID actorId) { this.actorId = actorId; }

    public String getActorUsername() { return actorUsername; }
    public void setActorUsername(String actorUsername) { this.actorUsername = actorUsername; }

    public String getRequestId() { return requestId; }
    public void setRequestId(String requestId) { this.requestId = requestId; }

    public String getSource() { return source; }
    public void setSource(String source) { this.source = source; }

    public String getClientIp() { return clientIp; }
    public void setClientIp(String clientIp) { this.clientIp = clientIp; }

    public String getUserAgent() { return userAgent; }
    public void setUserAgent(String userAgent) { this.userAgent = userAgent; }

    public String getTokenJti() { return tokenJti; }
    public void setTokenJti(String tokenJti) { this.tokenJti = tokenJti; }

    public String getSeverity() { return severity; }
    public void setSeverity(String severity) { this.severity = severity; }

    public Map<String, Object> getPayload() { return payload; }
    public void setPayload(Map<String, Object> payload) { this.payload = payload; }

    public OffsetDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(OffsetDateTime createdAt) { this.createdAt = createdAt; }
}

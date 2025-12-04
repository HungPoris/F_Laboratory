package fpt.com.laboratorymanagementbackend.common.audit.dto;

import java.time.OffsetDateTime;

public class AuditLogDto {
    private String id;
    private String event;
    private String userId;
    private String username;
    private String actorId;
    private String actorUsername;
    private String requestId;
    private String source;
    private String clientIp;
    private String userAgent;
    private String tokenJti;
    private String severity;
    private Object payload;
    private OffsetDateTime createdAtUtc;
    private String createdAtLocal;

    public AuditLogDto() {}

    public AuditLogDto(String id, String event, String userId, String username, String actorId, String actorUsername,
                       String requestId, String source, String clientIp, String userAgent, String tokenJti,
                       String severity, Object payload, OffsetDateTime createdAtUtc, String createdAtLocal) {
        this.id = id;
        this.event = event;
        this.userId = userId;
        this.username = username;
        this.actorId = actorId;
        this.actorUsername = actorUsername;
        this.requestId = requestId;
        this.source = source;
        this.clientIp = clientIp;
        this.userAgent = userAgent;
        this.tokenJti = tokenJti;
        this.severity = severity;
        this.payload = payload;
        this.createdAtUtc = createdAtUtc;
        this.createdAtLocal = createdAtLocal;
    }

    public String getId() { return id; }
    public void setId(String id) { this.id = id; }
    public String getEvent() { return event; }
    public void setEvent(String event) { this.event = event; }
    public String getUserId() { return userId; }
    public void setUserId(String userId) { this.userId = userId; }
    public String getUsername() { return username; }
    public void setUsername(String username) { this.username = username; }
    public String getActorId() { return actorId; }
    public void setActorId(String actorId) { this.actorId = actorId; }
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
    public Object getPayload() { return payload; }
    public void setPayload(Object payload) { this.payload = payload; }
    public OffsetDateTime getCreatedAtUtc() { return createdAtUtc; }
    public void setCreatedAtUtc(OffsetDateTime createdAtUtc) { this.createdAtUtc = createdAtUtc; }
    public String getCreatedAtLocal() { return createdAtLocal; }
    public void setCreatedAtLocal(String createdAtLocal) { this.createdAtLocal = createdAtLocal; }
}

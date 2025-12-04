package fpt.com.laboratorymanagementbackend.common.outbox.entity;

import jakarta.persistence.*;
import java.time.OffsetDateTime;
import java.util.UUID;

@Entity
@Table(name = "outbox_events", schema = "iamservice_db")
public class OutboxEvent {
    @Id
    @Column(name = "event_id", nullable = false)
    private UUID eventId;
    @Column(name = "topic")
    private String topic;
    @Lob
    @Column(name = "payload", columnDefinition = "TEXT")
    private String payload;
    @Column(name = "created_at")
    private OffsetDateTime createdAt;
    @Column(name = "sent")
    private Boolean sent;
    @Column(name = "sent_at")
    private OffsetDateTime sentAt;
    public OutboxEvent() {}
    public UUID getEventId() { return eventId; }
    public void setEventId(UUID eventId) { this.eventId = eventId; }
    public String getTopic() { return topic; }
    public void setTopic(String topic) { this.topic = topic; }
    public String getPayload() { return payload; }
    public void setPayload(String payload) { this.payload = payload; }
    public OffsetDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(OffsetDateTime createdAt) { this.createdAt = createdAt; }
    public Boolean getSent() { return sent; }
    public void setSent(Boolean sent) { this.sent = sent; }
    public OffsetDateTime getSentAt() { return sentAt; }
    public void setSentAt(OffsetDateTime sentAt) { this.sentAt = sentAt; }
}

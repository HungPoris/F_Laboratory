package fpt.com.laboratorymanagementbackend.domain.iam.refresh.entity;

import jakarta.persistence.*;
import lombok.*;
import java.time.OffsetDateTime;
import java.util.UUID;

@Entity
@Table(name = "refresh_tokens", schema = "iamservice_db")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class RefreshToken {
    @Id
    @Column(name = "token_id", nullable = false)
    private UUID tokenId;
    @Column(name = "user_id", nullable = false)
    private UUID userId;
    @Column(name = "token_hash", nullable = false, length = 512)
    private String tokenHash;
    @Column(name = "token_family_id", nullable = false)
    private UUID tokenFamilyId;
    @Column(name = "access_token_jti")
    private String accessTokenJti;
    @Column(name = "ip_address", columnDefinition = "inet")
    private String ipAddress;
    @Column(name = "user_agent")
    private String userAgent;
    @Column(name = "created_at")
    private OffsetDateTime createdAt;
    @Column(name = "expires_at")
    private OffsetDateTime expiresAt;
    @Column(name = "last_used_at")
    private OffsetDateTime lastUsedAt;
    @Column(name = "is_active")
    private Boolean isActive;
    @Column(name = "is_revoked")
    private Boolean isRevoked;
    @Column(name = "revoked_at")
    private OffsetDateTime revokedAt;
    @Column(name = "revoked_reason")
    private String revokedReason;

    @PrePersist
    public void prePersist() {
        if (tokenId == null) tokenId = UUID.randomUUID();
        if (tokenFamilyId == null) tokenFamilyId = UUID.randomUUID();
        if (createdAt == null) createdAt = OffsetDateTime.now();
        if (isActive == null) isActive = true;
        if (isRevoked == null) isRevoked = false;
        if (lastUsedAt == null) lastUsedAt = OffsetDateTime.now();
    }
}

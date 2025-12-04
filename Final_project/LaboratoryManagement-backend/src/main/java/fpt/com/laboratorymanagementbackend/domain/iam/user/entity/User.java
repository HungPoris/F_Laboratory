package fpt.com.laboratorymanagementbackend.domain.iam.user.entity;

import fpt.com.laboratorymanagementbackend.domain.iam.role.entity.Role;
import jakarta.persistence.*;
import lombok.*;
import java.time.OffsetDateTime;
import java.time.LocalDate;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;

@Entity
@Table(name = "users", schema = "iamservice_db", indexes = {
        @Index(name = "idx_users_email_ci", columnList = "email"),
        @Index(name = "idx_users_username_ci", columnList = "username")
})
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class User {
    @Id
    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "username", nullable = false, unique = true, columnDefinition = "citext")
    private String username;

    @Column(name = "email", nullable = false, columnDefinition = "citext")
    private String email;

    @Column(name = "phone_number", length = 20)
    private String phoneNumber;

    @Column(name = "full_name", nullable = false)
    private String fullName;

    @Column(name = "identity_number", length = 50)
    private String identityNumber;

    @Column(name = "gender", length = 10)
    private String gender;

    @Column(name = "date_of_birth")
    private LocalDate dateOfBirth;

    @Column(name = "address", columnDefinition = "TEXT")
    private String address;

    @Column(name = "age_years", insertable = false, updatable = false)
    private Integer ageYears;

    @Column(name = "password_hash")
    private String passwordHash;

    @Column(name = "password_algorithm", length = 20)
    private String passwordAlgorithm;

    @Column(name = "password_updated_at")
    private OffsetDateTime passwordUpdatedAt;

    @Column(name = "password_expires_at")
    private OffsetDateTime passwordExpiresAt;

    @Column(name = "must_change_password")
    private Boolean mustChangePassword = false;

    @Column(name = "is_active")
    private Boolean isActive;

    @Column(name = "is_locked")
    private Boolean isLocked;

    @Column(name = "locked_at")
    private OffsetDateTime lockedAt;

    @Column(name = "locked_until")
    private OffsetDateTime lockedUntil;

    @Column(name = "locked_reason", columnDefinition = "TEXT")
    private String lockedReason;

    @Column(name = "failed_login_attempts")
    private Integer failedLoginAttempts;

    @Column(name = "last_failed_login_at")
    private OffsetDateTime lastFailedLoginAt;

    @Column(name = "last_successful_login_at")
    private OffsetDateTime lastSuccessfulLoginAt;

    @Column(name = "last_activity_at")
    private OffsetDateTime lastActivityAt;

    @Column(name = "last_login_user_agent", columnDefinition = "TEXT")
    private String lastLoginUserAgent;

    @Column(name = "created_at")
    private OffsetDateTime createdAt;

    @Column(name = "created_by")
    private UUID createdBy;

    @Column(name = "updated_at")
    private OffsetDateTime updatedAt;

    @Column(name = "updated_by")
    private UUID updatedBy;

    @ManyToMany(fetch = FetchType.LAZY)
    @JoinTable(
            name = "user_roles",
            schema = "iamservice_db",
            joinColumns = @JoinColumn(name = "user_id"),
            inverseJoinColumns = @JoinColumn(name = "role_id")
    )
    private Set<Role> roles = new HashSet<>();

    @PrePersist
    public void prePersist() {
        if (userId == null) userId = UUID.randomUUID();
        if (isActive == null) isActive = true;
        if (isLocked == null) isLocked = false;
        if (mustChangePassword == null) mustChangePassword = false;
        if (failedLoginAttempts == null) failedLoginAttempts = 0;
        if (createdAt == null) createdAt = OffsetDateTime.now();
        if (updatedAt == null) updatedAt = OffsetDateTime.now();
        if (passwordAlgorithm == null) passwordAlgorithm = "ARGON2ID";
        if (passwordUpdatedAt == null) passwordUpdatedAt = OffsetDateTime.now();
    }

    @PreUpdate
    public void preUpdate() {
        updatedAt = OffsetDateTime.now();
    }
}

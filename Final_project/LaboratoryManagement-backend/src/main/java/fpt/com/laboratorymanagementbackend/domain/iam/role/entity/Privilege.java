package fpt.com.laboratorymanagementbackend.domain.iam.role.entity;

import com.fasterxml.jackson.annotation.JsonIgnore;
import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;
import org.hibernate.annotations.CreationTimestamp;
import org.hibernate.annotations.UpdateTimestamp;

import java.time.OffsetDateTime;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;

@Getter
@Setter
@Entity
@Table(name = "privileges", schema = "iamservice_db")
public class Privilege {

    @Id
    @GeneratedValue
    @Column(name = "privilege_id", nullable = false)
    private UUID privilegeId;

    @Column(name = "privilege_code", nullable = false, unique = true, length = 100)
    private String privilegeCode;

    @Column(name = "privilege_name", nullable = false, length = 255)
    private String privilegeName;

    @Column(name = "privilege_description")
    private String privilegeDescription;

    @Column(name = "privilege_category", length = 50)
    private String privilegeCategory;

    @Column(name = "is_active", nullable = false)
    private boolean isActive = true;

    @CreationTimestamp
    @Column(name = "created_at", updatable = false)
    private OffsetDateTime createdAt;

    @UpdateTimestamp
    @Column(name = "updated_at")
    private OffsetDateTime updatedAt;

    @JsonIgnore
    @ManyToMany(mappedBy = "privileges", fetch = FetchType.LAZY)
    private Set<Role> roles = new HashSet<>();
}

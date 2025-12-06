package fpt.com.testorderservices.domain.masterdata.entity;

import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.CreationTimestamp;

import java.time.LocalDateTime;
import java.util.UUID;

@Entity
@Table(name = "test_types")
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class TestType {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    @Column(name = "test_type_id")
    private UUID id;

    @Column(name = "code", unique = true, nullable = false, length = 50)
    private String code;

    @Column(name = "name", nullable = false, length = 200)
    private String name;

    private String description;

    private String category;

    private String method;

    private String unit;

    @Column(name = "reference_min")
    private Double referenceMin;

    @Column(name = "reference_max")
    private Double referenceMax;

    @CreationTimestamp
    @Column(name = "created_at")
    private LocalDateTime createdAt;

    @Column(name = "updated_at")
    private LocalDateTime updatedAt;
}

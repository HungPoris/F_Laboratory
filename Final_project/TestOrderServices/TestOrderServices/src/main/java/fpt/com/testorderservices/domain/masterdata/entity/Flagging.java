package fpt.com.testorderservices.domain.masterdata.entity;

import jakarta.persistence.*;
import lombok.*;

import java.time.OffsetDateTime;
import java.util.UUID;

@Entity
@Table(name = "flagging_configurations")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Flagging {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    @Column(name = "config_id")
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "test_type_id", nullable = false)
    private TestType testType;

    @Column(name = "rule_name", length = 200)
    private String ruleName;

    @Column(name = "condition_type", nullable = false)
    private String conditionType;

    @Column(name = "min_value")
    private Double minValue;

    @Column(name = "max_value")
    private Double maxValue;

    @Column(name = "target_value")
    private Double targetValue;

    @Column(name = "flag_level", length = 50)
    private String flagLevel;

    @Column(name = "flag_color", length = 20)
    private String flagColor;

    @Column(name = "is_active")
    private Boolean isActive;

    @Column(name = "version_number")
    private Integer versionNumber;

    @Column(name = "created_at")
    private OffsetDateTime createdAt;

    @Column(name = "updated_at")
    private OffsetDateTime updatedAt;
}

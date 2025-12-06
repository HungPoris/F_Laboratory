package fpt.com.testorderservices.domain.result.entity;

import fpt.com.testorderservices.domain.comment.entity.Comment;
import fpt.com.testorderservices.domain.testorder.entity.TestOrder;
import fpt.com.testorderservices.domain.testorder.entity.TestOrderItem;
import fpt.com.testorderservices.domain.masterdata.entity.TestType;
import jakarta.persistence.*;
import lombok.*;

import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@Entity
@Table(name = "test_results")
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class TestResult {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    @Column(name = "test_result_id")
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "test_order_item_id", nullable = false)
    private TestOrderItem testOrderItem;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "test_type_id", nullable = false)
    private TestType testType;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "test_order_id", nullable = false)
    private TestOrder testOrder;

    @Column(name = "instrument_id")
    private UUID instrumentId;

    @Column(name = "reagent_id")
    private UUID reagentId;

    @Column(name = "result_value")
    private Double resultValue;

    @Column(name = "result_text", columnDefinition = "TEXT")
    private String resultText;

    @Column(name = "result_unit")
    private String resultUnit;

    @Column(name = "reference_range_min")
    private Double referenceRangeMin;

    @Column(name = "reference_range_max")
    private Double referenceRangeMax;

    @Column(name = "interpretation", columnDefinition = "TEXT")
    private String interpretation;


    @Column(name = "processed_at")
    private OffsetDateTime processedAt;

    @Column(name = "processed_by")
    private UUID processedBy;

    @Column(name = "reviewed_at")
    private OffsetDateTime reviewedAt;

    @Column(name = "reviewed_by")
    private UUID reviewedBy;

    @Column(name = "version_number")
    private Integer versionNumber;

    @Column(name = "flag_type", length = 50)
    private String flagType;

    @OneToMany(mappedBy = "testResult", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<Comment> comments = new ArrayList<>();
}

package fpt.com.testorderservices.domain.testorder.entity;

import fpt.com.testorderservices.domain.masterdata.entity.TestType;
import jakarta.persistence.*;
import lombok.*;

import java.time.OffsetDateTime;
import java.util.UUID;

@Entity
@Table(name = "test_order_items")
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class TestOrderItem {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    @Column(name = "test_order_item_id")
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "test_order_id", nullable = false)
    private TestOrder testOrder;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "test_type_id", nullable = false)
    private TestType testType;

    @Column(name = "status", length = 50)
    private String status = "PENDING";

    @Column(name = "created_at")
    private OffsetDateTime createdAt = OffsetDateTime.now();

    private String flagType;

}

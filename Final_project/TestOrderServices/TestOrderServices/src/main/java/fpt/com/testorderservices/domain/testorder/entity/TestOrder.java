package fpt.com.testorderservices.domain.testorder.entity;

import com.fasterxml.jackson.annotation.JsonIgnore;
import fpt.com.testorderservices.domain.medicalrecord.entity.MedicalRecord;
import fpt.com.testorderservices.domain.result.entity.TestResult;
import fpt.com.testorderservices.domain.comment.entity.Comment;

import jakarta.persistence.*;
import lombok.*;

import java.time.OffsetDateTime;
import java.util.*;

@Entity
@Table(name = "test_orders")
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class TestOrder {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    @Column(name = "test_order_id")
    private UUID id;

    @Column(name = "order_number", nullable = false, unique = true, length = 50)
    private String orderNumber;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "medical_record_id", nullable = false)
    private MedicalRecord medicalRecord;

    @Column(name = "patient_name", length = 200)
    private String patientName;

    private Integer age;

    @Column(length = 10)
    private String gender;

    @Column(name = "phone_number", length = 50)
    private String phoneNumber;

    @Column(length = 150)
    private String email;

    @Column(columnDefinition = "TEXT")
    private String address;

    @Column(name = "date_of_birth")
    private Date dateOfBirth;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", length = 50)
    private TestOrderStatus status = TestOrderStatus.PENDING;

    @Enumerated(EnumType.STRING)
    @Column(name = "priority", length = 50)
    private TestOrderPriority priority = TestOrderPriority.NORMAL;

    @Column(name = "clinical_notes", columnDefinition = "TEXT")
    private String clinicalNotes;

    @Column(name = "medical_record_snapshot", columnDefinition = "TEXT")
    private String medicalRecordSnapshot;


    @Column(name = "is_deleted")
    private boolean isDeleted = false;

    @Column(name = "created_at")
    private OffsetDateTime createdAt = OffsetDateTime.now();

    @Column(name = "updated_at")
    private OffsetDateTime updatedAt;

    @Column(name = "created_by")
    private UUID createdBy;

    @Column(name = "updated_by")
    private UUID updatedBy;

    @Column(name = "run_at")
    private OffsetDateTime runAt;

    @Column(name = "run_by")
    private UUID runBy;

    @Column(name = "reviewed_at")
    private OffsetDateTime reviewedAt;

    @Column(name = "reviewed_by")
    private UUID reviewedBy;


    @OneToMany(mappedBy = "testOrder", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<Comment> comments = new ArrayList<>();

    @OneToMany(mappedBy = "testOrder", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<TestOrderItem> items = new ArrayList<>();


}

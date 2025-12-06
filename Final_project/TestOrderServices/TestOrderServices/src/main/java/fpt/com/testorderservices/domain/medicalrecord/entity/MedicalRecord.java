package fpt.com.testorderservices.domain.medicalrecord.entity;

import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.vladmihalcea.hibernate.type.json.JsonType;
import fpt.com.testorderservices.domain.patient.entity.Patient;
import fpt.com.testorderservices.domain.testorder.entity.TestOrder;
import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.GenericGenerator;
import org.hibernate.annotations.Type;
import org.springframework.data.annotation.CreatedBy;
import org.springframework.data.annotation.CreatedDate;
import org.springframework.data.annotation.LastModifiedBy;
import org.springframework.data.annotation.LastModifiedDate;
import org.springframework.data.jpa.domain.support.AuditingEntityListener;

import java.time.LocalDateTime;
import java.util.*;

@Entity
@Table(name = "medical_records")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
@EntityListeners(AuditingEntityListener.class) // ✅ [QUAN TRỌNG] Kích hoạt Auditing
public class MedicalRecord {

    @Id
    @GeneratedValue(generator = "UUID")
    @GenericGenerator(name = "UUID", strategy = "org.hibernate.id.UUIDGenerator")
    @Column(name = "medical_record_id", updatable = false, nullable = false)
    private UUID medicalRecordId;

    @Column(name = "patient_id", nullable = false)
    private UUID patientId;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "patient_id", insertable = false, updatable = false)
    @JsonIgnoreProperties({"medicalRecords", "hibernateLazyInitializer", "handler"})
    @JsonIgnore
    private Patient patient;

    @Column(name = "record_code", unique = true, nullable = false)
    private String recordCode;

    private LocalDateTime visitDate;
    private String chiefComplaint;
    private String diagnosis;

    @Type(JsonType.class)
    @Column(name = "clinical_notes", columnDefinition = "jsonb")
    private Map<String, Object> clinicalNotes;

    @Type(JsonType.class)
    @Column(name = "test_order_ids", columnDefinition = "jsonb")
    private List<String> testOrderIds;

    @Type(JsonType.class)
    @Column(name = "department", columnDefinition = "jsonb")
    private List<String> departments;

    private LocalDateTime lastTestDate;

    // 🔹 Metadata [ĐÃ SỬA: Thêm Annotation Auditing]

    @CreatedBy // ✅ Tự động lấy User ID khi tạo
    @Column(updatable = false)
    private UUID createdBy;

    @LastModifiedBy // ✅ Tự động lấy User ID khi update
    private UUID updatedBy;

    private Boolean isDeleted = false;
    private LocalDateTime deletedAt;
    private UUID deletedBy;

    @CreatedDate // ✅ Tự động set thời gian tạo
    @Column(updatable = false)
    private LocalDateTime createdAt;

    @LastModifiedDate // ✅ Tự động set thời gian update
    private LocalDateTime updatedAt;

    @Version // (Optional) Optimistic locking
    private Long version = 0L;

    @OneToMany(mappedBy = "medicalRecord", cascade = CascadeType.ALL, fetch = FetchType.LAZY)
    @JsonIgnore
    private List<TestOrder> testOrders = new ArrayList<>();
}
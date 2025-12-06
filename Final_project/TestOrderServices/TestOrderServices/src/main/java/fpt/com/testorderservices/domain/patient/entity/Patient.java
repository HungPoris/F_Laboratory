package fpt.com.testorderservices.domain.patient.entity;

import com.fasterxml.jackson.annotation.JsonIgnore;
import fpt.com.testorderservices.domain.medicalrecord.entity.MedicalRecord;
import jakarta.persistence.*;
import lombok.*;
import org.springframework.data.annotation.CreatedBy;
import org.springframework.data.annotation.CreatedDate;
import org.springframework.data.annotation.LastModifiedBy;
import org.springframework.data.annotation.LastModifiedDate;
import org.springframework.data.jpa.domain.support.AuditingEntityListener;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@Entity
@Table(name = "patients")
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
@EntityListeners(AuditingEntityListener.class) // ✅ Quan trọng: Kích hoạt lắng nghe sự kiện Audit
public class Patient {
    @Id
    @GeneratedValue
    private UUID patientId;

    private String fullName;
    private LocalDate dob;
    private String gender;
    private String contactNumber;

    private String email;

    private String address;
    private LocalDateTime lastTestDate;

    // ✅ Tự động lấy User ID từ SecurityContext khi tạo
    @CreatedBy
    @Column(name = "created_by", updatable = false)
    private UUID createdBy;

    // ✅ Tự động lấy User ID từ SecurityContext khi update
    @LastModifiedBy
    @Column(name = "updated_by")
    private UUID updatedBy;

    private Boolean isDeleted = false;
    private LocalDateTime deletedAt;
    private UUID deletedBy;

    // ✅ Tự động lấy thời gian
    @CreatedDate
    @Column(name = "created_at", updatable = false)
    private LocalDateTime createdAt;

    // ✅ Tự động cập nhật thời gian
    @LastModifiedDate
    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    @JsonIgnore
    @OneToMany(mappedBy = "patient", cascade = CascadeType.ALL)
    private List<MedicalRecord> medicalRecords = new ArrayList<>();
}
package fpt.com.testorderservices.domain.medicalrecord.entity;

import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDateTime;
import java.util.UUID;
import org.hibernate.annotations.GenericGenerator;

@Entity
@Table(name = "medical_record_history")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class MedicalRecordHistory {

    @Id
    @GeneratedValue(generator = "UUID")
    @GenericGenerator(name = "UUID", strategy = "org.hibernate.id.UUIDGenerator")
    @Column(name = "history_id", updatable = false, nullable = false)
    private UUID historyId;

    private UUID medicalRecordId;

    @Column(columnDefinition = "jsonb")
    private String snapshot;

    private String action;
    private UUID actionBy;
    private LocalDateTime actionAt = LocalDateTime.now();
}

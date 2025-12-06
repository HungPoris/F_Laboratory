package fpt.com.testorderservices.domain.medicalrecord.entity;

import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDateTime;
import java.util.UUID;
import org.hibernate.annotations.GenericGenerator;

@Entity
@Table(name = "medical_record_access_log")
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class MedicalRecordAccessLog {

    @Id
    @GeneratedValue(generator = "UUID")
    @GenericGenerator(name = "UUID", strategy = "org.hibernate.id.UUIDGenerator")
    @Column(name = "log_id", updatable = false, nullable = false)
    private UUID logId;

    private UUID medicalRecordId;
    private UUID userId;
    private String username;
    private String action;
    private String clientIp;
    private String userAgent;
    private LocalDateTime timestamp = LocalDateTime.now();
    private String reason;
}

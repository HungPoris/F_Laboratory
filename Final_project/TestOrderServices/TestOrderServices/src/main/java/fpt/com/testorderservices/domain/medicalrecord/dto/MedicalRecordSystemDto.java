package fpt.com.testorderservices.domain.medicalrecord.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class MedicalRecordSystemDto {
    private UUID medicalRecordId;
    private UUID patientId;
    private String recordCode;
    private String patientName;
    private String department;
    // Các trường tùy chỉnh thêm
    private String diagnosis;
    private LocalDateTime visitDate;
    private LocalDateTime lastTestDate;
}
package fpt.com.testorderservices.domain.medicalrecord.dto;

import fpt.com.testorderservices.domain.patient.entity.Patient;
import lombok.*;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class MedicalRecordDto {

    private UUID medicalRecordId;
    private UUID patientId;
    private String recordCode;
    private LocalDateTime visitDate;
    private String chiefComplaint;
    private String diagnosis;

    // Các trường JSONB
    private Map<String, Object> clinicalNotes;
    private List<String> testOrderIds;

    private LocalDateTime lastTestDate;

    // Metadata
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;

    // 🔹 Thay vì chỉ trả về UUID, ta trả về Object chứa thông tin user
    private UserSummary createdBy;
    private UserSummary updatedBy;
//day
    private List<String> departments;


    // Nested class để chứa thông tin tóm tắt của User
    @Data
    @AllArgsConstructor
    @NoArgsConstructor
    @Builder
    public static class UserSummary {
        private UUID id;
        private String fullName;
    }
}
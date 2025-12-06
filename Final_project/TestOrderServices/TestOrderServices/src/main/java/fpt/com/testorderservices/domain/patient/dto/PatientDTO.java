package fpt.com.testorderservices.domain.patient.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class PatientDTO {
    private UUID patientId;
    private String fullName;
    private LocalDate dob;
    private String gender;
    private String contactNumber;
    private String email;
    private String address;
    private LocalDateTime lastTestDate;

    // 🔹 Thay đổi thành Object để chứa id và username
    private UserSummary createdBy;
    private UserSummary updatedBy;

    private Boolean isDeleted;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;

    // 🔹 Class con để định dạng {userID, userName}
    @Data
    @AllArgsConstructor
    @NoArgsConstructor
    @Builder
    public static class UserSummary {
        private UUID userID;    // Đổi tên field để khớp JSON: {"userID": "..."}
        private String userName; // Đổi tên field để khớp JSON: {"userName": "..."}
    }
}
package fpt.com.testorderservices.domain.testorder.dto;

import fpt.com.testorderservices.domain.comment.dto.CommentDto;
import fpt.com.testorderservices.domain.testorder.entity.*;
import lombok.*;
import java.time.OffsetDateTime;
import java.util.*;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class TestOrderDto {

    private UUID id;
    private String orderNumber;
    private UUID medicalRecordId;
    private UUID patientId;
    private String patientName;
    private Integer age;
    private String gender;
    private String phoneNumber;
    private String email;
    private String address;
    private Date dateOfBirth;
    private TestOrderStatus status;
    private TestOrderPriority priority;
    private String clinicalNotes;
    private String medicalRecordSnapshot;
    private OffsetDateTime createdAt;
    private OffsetDateTime updatedAt;
    private OffsetDateTime runAt;
    private OffsetDateTime reviewedAt;
    private UserSummary createdBy;
    private UserSummary updatedBy;
    private UserSummary runBy;
    private UserSummary reviewedBy;
    private List<UUID> testResultIds;
    private List<CommentDto> comments;
    private List<UUID> testTypeIds;
    private List<TestOrderItemDto> items;
    @Data
    @AllArgsConstructor
    @NoArgsConstructor
    public static class UserSummary {
        private UUID id;
        private String username;
    }
}

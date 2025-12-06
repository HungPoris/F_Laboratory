package fpt.com.testorderservices.domain.comment.dto;

import fpt.com.testorderservices.domain.comment.entity.CommentType;
import lombok.*;
import java.time.OffsetDateTime;
import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class CommentDto {

    private UUID id;
    private UUID testOrderId;
    private UUID testResultId;

    private String commentText;
    private CommentType commentType;


    private OffsetDateTime createdAt;
    private OffsetDateTime updatedAt;

    private UserSummary createdBy;
    private UserSummary updatedBy;

    private String eventType;

    @Data
    @AllArgsConstructor
    @NoArgsConstructor
    public static class UserSummary {
        private UUID id;
        private String fullName;
    }
}

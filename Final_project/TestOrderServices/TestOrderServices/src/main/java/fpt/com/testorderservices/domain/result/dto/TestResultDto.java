    package fpt.com.testorderservices.domain.result.dto;

    import fpt.com.testorderservices.domain.comment.dto.CommentDto;
    import lombok.*;
    import java.time.OffsetDateTime;
    import java.util.List;
    import java.util.UUID;

    @Data
    @Builder
    @NoArgsConstructor
    @AllArgsConstructor
    public class TestResultDto {

        private String testTypeName;
        private String instrumentName;
        private String reagentName;
        private UUID id;
        private UUID testOrderId;
        private UUID testOrderItemId;
        private UUID testTypeId;
        private UUID instrumentId;
        private UUID reagentId;
        private Double resultValue;
        private String resultText;
        private String resultUnit;
        private Double referenceRangeMin;
        private Double referenceRangeMax;
        private String interpretation;
        private String flagType;
        private OffsetDateTime processedAt;
        private OffsetDateTime reviewedAt;
        private UserSummary processedBy;
        private UserSummary reviewedBy;
        private Integer versionNumber;
        private List<CommentDto> comments;

        @Data
        @AllArgsConstructor
        @NoArgsConstructor
        public static class UserSummary {
            private UUID id;
            private String username;
        }
    }

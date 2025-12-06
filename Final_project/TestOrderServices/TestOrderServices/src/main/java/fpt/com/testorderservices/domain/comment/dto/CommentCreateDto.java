package fpt.com.testorderservices.domain.comment.dto;

import fpt.com.testorderservices.domain.comment.entity.CommentType;
import lombok.*;
import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class CommentCreateDto {

    private UUID testOrderId;
    private UUID testResultId;
    private String commentText;
    private CommentType commentType;

}

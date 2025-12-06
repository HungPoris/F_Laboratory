package fpt.com.testorderservices.domain.comment.dto;

import fpt.com.testorderservices.domain.comment.entity.CommentType;
import lombok.*;
import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class CommentUpdateDto {

    private String commentText;
    private CommentType commentType;


    private UUID updatedBy;
}

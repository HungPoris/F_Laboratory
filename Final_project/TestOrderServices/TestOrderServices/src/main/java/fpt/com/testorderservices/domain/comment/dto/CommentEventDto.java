package fpt.com.testorderservices.domain.comment.dto;



import lombok.*;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class CommentEventDto {

    private String type;
    private CommentDto data;
}

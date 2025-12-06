package fpt.com.testorderservices.domain.result.dto;

import lombok.*;
import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class TestResultCreateDto {

    private UUID testOrderItemId;
    private Double resultValue;
    private String resultUnit;
    private String resultText;
    private String interpretation;
}

package fpt.com.testorderservices.domain.result.dto;

import lombok.*;


@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class TestResultUpdateDto {

    private Double resultValue;
    private String resultText;
    private String resultUnit;
    private Double referenceRangeMin;
    private Double referenceRangeMax;
    private String interpretation;

}

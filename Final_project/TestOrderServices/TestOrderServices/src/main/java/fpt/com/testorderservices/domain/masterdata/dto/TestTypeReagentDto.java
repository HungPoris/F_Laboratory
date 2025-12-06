package fpt.com.testorderservices.domain.masterdata.dto;

import lombok.*;
import java.util.UUID;

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class TestTypeReagentDto {

    private UUID id;
    private UUID testTypeId;
    private String testTypeCode;
    private String testTypeName;
    private UUID reagentId;
    private String reagentName;
}

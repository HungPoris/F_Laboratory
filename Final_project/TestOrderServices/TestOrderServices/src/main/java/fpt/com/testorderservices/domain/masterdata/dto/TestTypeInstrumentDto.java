package fpt.com.testorderservices.domain.masterdata.dto;

import lombok.*;
import java.util.UUID;

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class TestTypeInstrumentDto {

    private UUID id;
    private UUID testTypeId;
    private String testTypeCode;
    private String testTypeName;
    private UUID instrumentId;
    private String instrumentCode;
    private String instrumentName;
}

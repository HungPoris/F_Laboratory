package fpt.com.testorderservices.domain.testorder.dto;

import lombok.*;
import java.util.UUID;

@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class TestOrderItemDto {

    private UUID id;
    private UUID testTypeId;
    private String testTypeCode;
    private String testTypeName;
    private String status;
    private String flagType;

}

package fpt.com.testorderservices.domain.testorder.dto;

import fpt.com.testorderservices.domain.testorder.entity.TestOrderPriority;
import lombok.*;
import java.util.Date;
import java.util.List;
import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class TestOrderCreateDto {

    private String orderNumber;
    private UUID medicalRecordId;
    private String email;
    private TestOrderPriority priority;
    private String clinicalNotes;
    private List<UUID> testTypeIds;
}

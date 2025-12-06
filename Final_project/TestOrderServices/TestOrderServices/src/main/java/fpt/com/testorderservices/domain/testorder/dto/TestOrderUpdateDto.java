package fpt.com.testorderservices.domain.testorder.dto;

import fpt.com.testorderservices.domain.testorder.entity.*;
import lombok.*;
import java.util.Date;
import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class TestOrderUpdateDto {

    private UUID medicalRecordId;
    private String email;
    private TestOrderStatus status;
    private TestOrderPriority priority;
    private String clinicalNotes;
}

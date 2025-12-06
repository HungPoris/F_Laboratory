package fpt.com.testorderservices.domain.masterdata.dto;

import java.time.LocalDateTime;
import java.util.UUID;
import lombok.Getter;
import lombok.AllArgsConstructor;

@Getter
@AllArgsConstructor
public class ReagentDto {
    private UUID id;
    private String name;
    private String batchNumber;
    private LocalDateTime expirationDate;
    private String supplier;
}

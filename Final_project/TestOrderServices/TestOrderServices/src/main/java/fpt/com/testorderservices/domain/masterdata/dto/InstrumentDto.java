package fpt.com.testorderservices.domain.masterdata.dto;

import java.time.LocalDateTime;
import java.util.UUID;
import lombok.Getter;
import lombok.AllArgsConstructor;

@Getter
@AllArgsConstructor
public class InstrumentDto {
    private UUID id;
    private String code;
    private String name;
    private String model;
    private String manufacturer;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
}

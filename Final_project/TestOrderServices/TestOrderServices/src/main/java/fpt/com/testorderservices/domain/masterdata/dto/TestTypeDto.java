package fpt.com.testorderservices.domain.masterdata.dto;

import java.time.LocalDateTime;
import java.util.UUID;
import lombok.Getter;
import lombok.AllArgsConstructor;

@Getter
@AllArgsConstructor
public class TestTypeDto {
    private UUID id;
    private String code;
    private String name;
    private String description;
    private String category;
    private String method;
    private String unit;
    private Double referenceMin;
    private Double referenceMax;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
}

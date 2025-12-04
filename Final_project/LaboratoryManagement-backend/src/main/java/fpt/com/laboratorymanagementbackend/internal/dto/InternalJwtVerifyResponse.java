package fpt.com.laboratorymanagementbackend.internal.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.List;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class InternalJwtVerifyResponse {
    private boolean valid;
    private String userId;
    private String username;
    private List<String> privileges;
    private String errorMessage;
}
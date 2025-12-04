package fpt.com.laboratorymanagementbackend.internal.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.util.UUID;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class InternalUserSummaryResponse {
    private UUID userId;
    private String username;
    private String fullName;
}
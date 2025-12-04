package fpt.com.laboratorymanagementbackend.domain.iam.role.dto;

import java.util.UUID;

public record RoleOptionResponse(
        UUID id,
        String code,
        String name
) {}


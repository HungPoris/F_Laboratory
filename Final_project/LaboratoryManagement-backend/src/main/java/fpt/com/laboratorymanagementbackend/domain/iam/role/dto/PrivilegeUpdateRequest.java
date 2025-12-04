package fpt.com.laboratorymanagementbackend.domain.iam.role.dto;

public record PrivilegeUpdateRequest(
        String name,
        String description,
        String category,
        boolean active
) {}


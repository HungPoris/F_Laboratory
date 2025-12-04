package fpt.com.laboratorymanagementbackend.domain.iam.role.dto;

public record PrivilegeCreateRequest(
        String code,
        String name,
        String description,
        String category,
        boolean active
) {}


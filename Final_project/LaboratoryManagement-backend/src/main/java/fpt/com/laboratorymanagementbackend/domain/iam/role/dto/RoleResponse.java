package fpt.com.laboratorymanagementbackend.domain.iam.role.dto;

import java.util.List;
import java.util.UUID;

public class RoleResponse {
    private UUID id;
    private String code;
    private String name;
    private String description;
    private boolean system;
    private boolean active;
    private List<String> privilegeCodes;

    public RoleResponse(UUID id, String code, String name, String description, boolean system, boolean active, List<String> privilegeCodes) {
        this.id = id;
        this.code = code;
        this.name = name;
        this.description = description;
        this.system = system;
        this.active = active;
        this.privilegeCodes = privilegeCodes;
    }

    public UUID getId() { return id; }
    public String getCode() { return code; }
    public String getName() { return name; }
    public String getDescription() { return description; }
    public boolean isSystem() { return system; }
    public boolean isActive() { return active; }
    public List<String> getPrivilegeCodes() { return privilegeCodes; }
}

package fpt.com.laboratorymanagementbackend.domain.iam.role.dto;

import java.util.List;
import java.util.UUID;

public class RoleUpdateRequest {
    private String name;
    private String description;
    private Boolean active;
    private Boolean system;
    private List<UUID> privilegeIds;

    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public String getDescription() { return description; }
    public void setDescription(String description) { this.description = description; }
    public Boolean getActive() { return active; }
    public void setActive(Boolean active) { this.active = active; }
    public Boolean getSystem() { return system; }
    public void setSystem(Boolean system) { this.system = system; }
    public List<UUID> getPrivilegeIds() { return privilegeIds; }
    public void setPrivilegeIds(List<UUID> privilegeIds) { this.privilegeIds = privilegeIds; }
}

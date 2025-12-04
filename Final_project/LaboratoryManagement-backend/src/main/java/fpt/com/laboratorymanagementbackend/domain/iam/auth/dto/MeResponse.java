package fpt.com.laboratorymanagementbackend.domain.iam.auth.dto;

import java.util.List;
import java.util.Set;

public class MeResponse {
    private String userId;
    private String username;
    private String fullName;
    private String email;
    private Set<String> roles;
    private Set<String> privileges;
    private Set<String> accessibleScreens;
    private List<ScreenDto> accessibleScreensDetailed;

    public MeResponse() {}

    public MeResponse(String userId, String username, String fullName, String email,
                      Set<String> roles, Set<String> privileges,
                      Set<String> accessibleScreens, List<ScreenDto> accessibleScreensDetailed) {
        this.userId = userId;
        this.username = username;
        this.fullName = fullName;
        this.email = email;
        this.roles = roles;
        this.privileges = privileges;
        this.accessibleScreens = accessibleScreens;
        this.accessibleScreensDetailed = accessibleScreensDetailed;
    }

    public String getUserId() { return userId; }
    public void setUserId(String userId) { this.userId = userId; }

    public String getUsername() { return username; }
    public void setUsername(String username) { this.username = username; }

    public String getFullName() { return fullName; }
    public void setFullName(String fullName) { this.fullName = fullName; }

    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }

    public Set<String> getRoles() { return roles; }
    public void setRoles(Set<String> roles) { this.roles = roles; }

    public Set<String> getPrivileges() { return privileges; }
    public void setPrivileges(Set<String> privileges) { this.privileges = privileges; }

    public Set<String> getAccessibleScreens() { return accessibleScreens; }
    public void setAccessibleScreens(Set<String> accessibleScreens) { this.accessibleScreens = accessibleScreens; }

    public List<ScreenDto> getAccessibleScreensDetailed() { return accessibleScreensDetailed; }
    public void setAccessibleScreensDetailed(List<ScreenDto> accessibleScreensDetailed) { this.accessibleScreensDetailed = accessibleScreensDetailed; }
}

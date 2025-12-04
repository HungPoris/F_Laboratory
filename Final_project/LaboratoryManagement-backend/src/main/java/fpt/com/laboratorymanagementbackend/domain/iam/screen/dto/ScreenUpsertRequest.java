package fpt.com.laboratorymanagementbackend.domain.iam.screen.dto;

import com.fasterxml.jackson.annotation.JsonProperty;

public class ScreenUpsertRequest {

    @JsonProperty("screen_code")
    private String screenCode;

    @JsonProperty("path")
    private String path;

    @JsonProperty("base_path")
    private String basePath;

    @JsonProperty("title")
    private String title;

    @JsonProperty("icon")
    private String icon;

    @JsonProperty("ordering")
    private Integer ordering;

    @JsonProperty("parent_code")
    private String parentCode;

    @JsonProperty("is_menu")
    private Boolean isMenu;

    @JsonProperty("is_public")
    private Boolean isPublic;

    @JsonProperty("is_active")
    private Boolean isActive;

    public ScreenUpsertRequest() {}

    public String getScreenCode() { return screenCode; }
    public void setScreenCode(String screenCode) { this.screenCode = screenCode; }
    public String getPath() { return path; }
    public void setPath(String path) { this.path = path; }
    public String getBasePath() { return basePath; }
    public void setBasePath(String basePath) { this.basePath = basePath; }
    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }
    public String getIcon() { return icon; }
    public void setIcon(String icon) { this.icon = icon; }
    public Integer getOrdering() { return ordering; }
    public void setOrdering(Integer ordering) { this.ordering = ordering; }
    public String getParentCode() { return parentCode; }
    public void setParentCode(String parentCode) { this.parentCode = parentCode; }
    public Boolean getIsMenu() { return isMenu; }
    public void setIsMenu(Boolean isMenu) { this.isMenu = isMenu; }
    public Boolean getIsPublic() { return isPublic; }
    public void setIsPublic(Boolean isPublic) { this.isPublic = isPublic; }
    public Boolean getIsActive() { return isActive; }
    public void setIsActive(Boolean isActive) { this.isActive = isActive; }
}

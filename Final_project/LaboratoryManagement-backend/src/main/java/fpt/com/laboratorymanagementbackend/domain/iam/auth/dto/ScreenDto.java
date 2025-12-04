package fpt.com.laboratorymanagementbackend.domain.iam.auth.dto;

public class ScreenDto {
    private String screenCode;
    private String path;
    private String basePath;
    private String title;
    private String icon;
    private Integer ordering;
    private Boolean isMenu;
    private String parentCode;

    public ScreenDto() {}

    public ScreenDto(String screenCode, String path, String basePath, String title, String icon, Integer ordering, Boolean isMenu, String parentCode) {
        this.screenCode = screenCode;
        this.path = path;
        this.basePath = basePath;
        this.title = title;
        this.icon = icon;
        this.ordering = ordering;
        this.isMenu = isMenu;
        this.parentCode = parentCode;
    }

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

    public Boolean getIsMenu() { return isMenu; }
    public void setIsMenu(Boolean isMenu) { this.isMenu = isMenu; }

    public String getParentCode() { return parentCode; }
    public void setParentCode(String parentCode) { this.parentCode = parentCode; }
}

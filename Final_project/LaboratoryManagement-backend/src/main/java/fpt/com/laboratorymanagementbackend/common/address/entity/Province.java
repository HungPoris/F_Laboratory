package fpt.com.laboratorymanagementbackend.common.address.entity;

import jakarta.persistence.*;

@Entity
@Table(name = "vn_province", schema = "iamservice_db")
public class Province {
    @Id
    private String code;
    private String name;
    private String englishName;
    private String decree;
    public String getCode() { return code; }
    public void setCode(String code) { this.code = code; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public String getEnglishName() { return englishName; }
    public void setEnglishName(String englishName) { this.englishName = englishName; }
    public String getDecree() { return decree; }
    public void setDecree(String decree) { this.decree = decree; }
}

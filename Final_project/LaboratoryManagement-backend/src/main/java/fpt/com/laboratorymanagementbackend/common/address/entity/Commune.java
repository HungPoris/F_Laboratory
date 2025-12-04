package fpt.com.laboratorymanagementbackend.common.address.entity;

import jakarta.persistence.*;

@Entity
@Table(name = "vn_commune", schema = "iamservice_db")
public class Commune {
    @Id
    @Column(name = "code", length = 50)
    private String code;

    @Column(name = "name", length = 255)
    private String name;

    @Column(name = "english_name", length = 255)
    private String englishName;

    @Column(name = "administrative_level", length = 32)
    private String administrativeLevel;

    @Column(name = "province_code", length = 50)
    private String provinceCode;

    @Column(name = "province_name", length = 255)
    private String provinceName;

    @Column(name = "decree", length = 255)
    private String decree;

    // Getters and Setters
    public String getCode() { return code; }
    public void setCode(String code) { this.code = code; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public String getEnglishName() { return englishName; }
    public void setEnglishName(String englishName) { this.englishName = englishName; }
    public String getAdministrativeLevel() { return administrativeLevel; }
    public void setAdministrativeLevel(String administrativeLevel) { this.administrativeLevel = administrativeLevel; }
    public String getProvinceCode() { return provinceCode; }
    public void setProvinceCode(String provinceCode) { this.provinceCode = provinceCode; }
    public String getProvinceName() { return provinceName; }
    public void setProvinceName(String provinceName) { this.provinceName = provinceName; }
    public String getDecree() { return decree; }
    public void setDecree(String decree) { this.decree = decree; }
}
package fpt.com.laboratorymanagementbackend.common.address.dto;

public class AddressInput {
    private String house;
    private String provinceCode;
    private String communeCode;
    public String getHouse() { return house; }
    public void setHouse(String house) { this.house = house; }
    public String getProvinceCode() { return provinceCode; }
    public void setProvinceCode(String provinceCode) { this.provinceCode = provinceCode; }
    public String getCommuneCode() { return communeCode; }
    public void setCommuneCode(String communeCode) { this.communeCode = communeCode; }
}

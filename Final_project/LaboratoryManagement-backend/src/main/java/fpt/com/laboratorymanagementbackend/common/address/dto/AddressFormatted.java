package fpt.com.laboratorymanagementbackend.common.address.dto;

public class AddressFormatted {
    private String fullAddress;
    private String provinceName;
    private String communeName;
    public AddressFormatted() {}
    public AddressFormatted(String fullAddress, String provinceName, String communeName) {
        this.fullAddress = fullAddress; this.provinceName = provinceName; this.communeName = communeName;
    }
    public String getFullAddress() { return fullAddress; }
    public void setFullAddress(String fullAddress) { this.fullAddress = fullAddress; }
    public String getProvinceName() { return provinceName; }
    public void setProvinceName(String provinceName) { this.provinceName = provinceName; }
    public String getCommuneName() { return communeName; }
    public void setCommuneName(String communeName) { this.communeName = communeName; }
}

package fpt.com.laboratorymanagementbackend.domain.iam.profile.dto;

import jakarta.validation.constraints.*;
import java.time.LocalDate;

public class UpdateMyProfileRequest {

    @Size(min = 4, max = 128, message = "FULL_NAME_SIZE")
    @Pattern(regexp = "^[\\p{L}\\s]+$", message = "FULL_NAME_PATTERN")
    private String fullName;

    @Pattern(regexp = "^\\d{10}$", message = "PHONE_INVALID")
    private String phoneNumber;

    @Past(message = "DATE_OF_BIRTH_PAST")
    private LocalDate dateOfBirth;

    @Pattern(regexp = "^\\d{12}$", message = "IDENTITY_INVALID")
    private String identityNumber;

    @Pattern(regexp = "^(male|female|orther)$", message = "GENDER_INVALID")
    private String gender;

    @Size(max = 255, message = "ADDRESS_SIZE")
    private String address;

    public String getFullName() { return fullName; }
    public void setFullName(String v) { this.fullName = v == null ? null : v.trim(); }

    public String getPhoneNumber() { return phoneNumber; }
    public void setPhoneNumber(String v) { this.phoneNumber = v == null ? null : v.trim(); }

    public LocalDate getDateOfBirth() { return dateOfBirth; }
    public void setDateOfBirth(LocalDate v) { this.dateOfBirth = v; }

    public String getIdentityNumber() { return identityNumber; }
    public void setIdentityNumber(String v) { this.identityNumber = v == null ? null : v.trim(); }

    public String getGender() { return gender; }
    public void setGender(String v) { this.gender = v; }

    public String getAddress() { return address; }
    public void setAddress(String v) { this.address = v; }
}

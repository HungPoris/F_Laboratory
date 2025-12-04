package fpt.com.laboratorymanagementbackend.domain.iam.user.dto;

import jakarta.validation.constraints.*;
import java.time.LocalDate;
import java.util.Set;

public class CreateUserAdminDto {

    @Pattern(regexp = "^[A-Za-z0-9._-]{3,32}$", message = "USERNAME_PATTERN")
    private String username;

    @NotBlank(message = "EMAIL_REQUIRED")
    @Email(message = "EMAIL_INVALID")
    @Size(max = 254, message = "EMAIL_SIZE")
    private String email;

    @NotBlank(message = "FULL_NAME_REQUIRED")
    @Size(min = 4, max = 128, message = "FULL_NAME_SIZE")
    @Pattern(regexp = "^[\\p{L}\\s]+$", message = "FULL_NAME_PATTERN")
    private String fullName;

    @Size(min = 8, max = 128, message = "PASSWORD_SIZE")
    private String password;

    @Pattern(regexp = "^\\d{10}$", message = "PHONE_INVALID")
    private String phoneNumber;

    @Past(message = "DATE_OF_BIRTH_PAST")
    private LocalDate dateOfBirth;

    @Size(max = 255, message = "ADDRESS_SIZE")
    private String address;

    @Pattern(regexp = "^\\d{12}$", message = "IDENTITY_INVALID")
    private String identityNumber;

    @Pattern(regexp = "^(male|female|other)$", message = "GENDER_INVALID")
    private String gender;

    private Set<String> roles;

    public String getUsername() { return username; }
    public void setUsername(String username) { this.username = username == null ? null : username.trim(); }

    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email == null ? null : email.trim().toLowerCase(); }

    public String getFullName() { return fullName; }
    public void setFullName(String fullName) { this.fullName = fullName == null ? null : fullName.trim(); }

    public String getPassword() { return password; }
    public void setPassword(String password) { this.password = password; }

    public String getPhoneNumber() { return phoneNumber; }
    public void setPhoneNumber(String phoneNumber) { this.phoneNumber = phoneNumber == null ? null : phoneNumber.trim(); }

    public LocalDate getDateOfBirth() { return dateOfBirth; }
    public void setDateOfBirth(LocalDate dateOfBirth) { this.dateOfBirth = dateOfBirth; }

    public String getAddress() { return address; }
    public void setAddress(String address) { this.address = address; }

    public String getIdentityNumber() { return identityNumber; }
    public void setIdentityNumber(String identityNumber) { this.identityNumber = identityNumber == null ? null : identityNumber.trim(); }

    public String getGender() { return gender; }
    public void setGender(String gender) { this.gender = gender; }

    public Set<String> getRoles() { return roles; }
    public void setRoles(Set<String> roles) { this.roles = roles; }
}

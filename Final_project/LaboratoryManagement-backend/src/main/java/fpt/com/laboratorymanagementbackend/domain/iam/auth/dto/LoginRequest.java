package fpt.com.laboratorymanagementbackend.domain.iam.auth.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public class LoginRequest {
    @NotBlank(message = "auth.username.required")
    @Size(max = 254, message = "auth.username.size")
    private String username;

    @NotBlank(message = "auth.password.required")
    @Size(max = 128, message = "auth.password.size")
    private String password;

    public String getUsername() {
        return username;
    }

    public void setUsername(String username) {
        this.username = username == null ? null : username.trim();
    }

    public String getPassword() {
        return password;
    }

    public void setPassword(String password) {
        this.password = password;
    }
}

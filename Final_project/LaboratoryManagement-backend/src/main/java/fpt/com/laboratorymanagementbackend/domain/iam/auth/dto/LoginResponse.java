package fpt.com.laboratorymanagementbackend.domain.iam.auth.dto;

public class LoginResponse {
    private String accessToken;

    public LoginResponse() {}

    public LoginResponse(String accessToken) {
        this.accessToken = accessToken;
    }

    public String getAccessToken() {
        return accessToken;
    }

    private Boolean mustChangePassword;


    public void setAccessToken(String accessToken) {
        this.accessToken = accessToken;
    }
}

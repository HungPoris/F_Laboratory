package fpt.com.laboratorymanagementbackend.domain.iam.auth.dto;

import lombok.Getter;
import lombok.Setter;
@Getter
@Setter
public class AuthResponse {
    private String accessToken;
    private String tokenType = "Bearer";
    private long expiresIn;
    private String refreshToken;
}

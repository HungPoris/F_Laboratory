package fpt.com.laboratorymanagementbackend.domain.iam.auth.dto;

import lombok.Getter;

@Getter
public class AuthFailureResponse {
    private String error;

    public AuthFailureResponse() {}

    public AuthFailureResponse(String error) {
        this.error = error;
    }

    public void setError(String error) {
        this.error = error;
    }
}

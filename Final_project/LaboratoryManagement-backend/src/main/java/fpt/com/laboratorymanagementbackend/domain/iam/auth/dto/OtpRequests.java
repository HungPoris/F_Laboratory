package fpt.com.laboratorymanagementbackend.domain.iam.auth.dto;

public class OtpRequests {
    public static class StartRequest {
        public String usernameOrEmail;
    }
    public static class VerifyRequest {
        public String userId;
        public String correlationId;
        public String otp;
    }
    public static class ResetRequest {
        public String userId;
        public String correlationId;
        public String newPassword;
    }
}

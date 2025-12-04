package fpt.com.laboratorymanagementbackend.domain.iam.auth.controller;

import org.springframework.web.bind.annotation.*;
import org.springframework.http.ResponseEntity;
import org.springframework.http.HttpStatus;
import fpt.com.laboratorymanagementbackend.domain.iam.auth.dto.OtpRequests;
import fpt.com.laboratorymanagementbackend.domain.iam.auth.service.OtpService;
import fpt.com.laboratorymanagementbackend.domain.iam.user.service.UserService;
import java.util.Map;
import java.util.Optional;
import jakarta.servlet.http.HttpServletRequest;

@RestController
@RequestMapping({"/api/v1/auth/forgot", "/auth/otp"})
public class OtpController {
    private final OtpService otpService;
    private final UserService userService;

    public OtpController(OtpService otpService, UserService userService) {
        this.otpService = otpService;
        this.userService = userService;
    }

    @PostMapping("/start")
    public ResponseEntity<?> start(@RequestBody OtpRequests.StartRequest req, HttpServletRequest http) {
        String ip = http.getRemoteAddr();
        String ua = http.getHeader("User-Agent");
        var opt = otpService.startForgot(req.usernameOrEmail, ip, ua);
        if (opt.isEmpty()) return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(Map.of("error","not_found_or_rate_limited"));
        return ResponseEntity.ok(opt.get());
    }

    @PostMapping("/send")
    public ResponseEntity<?> sendLegacy(@RequestBody Map<String, Object> body, HttpServletRequest http) {
        String usernameOrEmail = extractUsernameOrEmail(body);
        if (usernameOrEmail == null || usernameOrEmail.isBlank()) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(Map.of("error", "missing_username_or_email"));
        }
        String ip = http.getRemoteAddr();
        String ua = http.getHeader("User-Agent");
        var opt = otpService.startForgot(usernameOrEmail, ip, ua);
        if (opt.isEmpty()) return ResponseEntity.status(HttpStatus.BAD_REQUEST).body(Map.of("error","not_found_or_rate_limited"));
        return ResponseEntity.ok(opt.get());
    }

    @PostMapping("/verify")
    public ResponseEntity<?> verify(@RequestBody OtpRequests.VerifyRequest req) {
        var r = otpService.verifyOtp(req.userId, req.correlationId, req.otp);
        switch (r) {
            case OK: return ResponseEntity.ok(Map.of("ok", true));
            case INVALID: return ResponseEntity.status(400).body(Map.of("error","invalid"));
            case BLOCKED: return ResponseEntity.status(403).body(Map.of("error","blocked"));
            case EXPIRED: return ResponseEntity.status(410).body(Map.of("error","expired"));
            default: return ResponseEntity.status(400).body(Map.of("error","invalid"));
        }
    }

    @PostMapping("/reset")
    public ResponseEntity<?> reset(@RequestBody OtpRequests.ResetRequest req) {
        boolean ok = otpService.resetPasswordIfVerified(req.userId, req.correlationId, req.newPassword, (userId, newPass) -> {
            userService.updatePassword(java.util.UUID.fromString(userId), newPass);
        });
        if (!ok) return ResponseEntity.status(400).body(Map.of("error","not_verified_or_invalid"));
        return ResponseEntity.ok(Map.of("ok", true));
    }

    private String extractUsernameOrEmail(Map<String, Object> body) {
        if (body == null) return null;
        Object v = body.get("usernameOrEmail");
        if (v == null) v = body.get("email");
        if (v == null) v = body.get("username");
        return v == null ? null : v.toString();
    }
}

package fpt.com.laboratorymanagementbackend.domain.iam.profile.controller;

import fpt.com.laboratorymanagementbackend.domain.iam.profile.dto.MyProfileResponse;
import fpt.com.laboratorymanagementbackend.domain.iam.profile.dto.UpdateMyProfileRequest;
import fpt.com.laboratorymanagementbackend.domain.iam.profile.dto.ChangePasswordRequest;
import fpt.com.laboratorymanagementbackend.domain.iam.auth.dto.ChangePasswordFirstLoginRequest;
import fpt.com.laboratorymanagementbackend.domain.iam.profile.service.MyProfileService;
import fpt.com.laboratorymanagementbackend.security.userdetails.UserPrincipal;
import fpt.com.laboratorymanagementbackend.common.service.OutboxService;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/profile")
public class MyProfileController {
    private final MyProfileService myProfileService;
    private final OutboxService outboxService;

    public MyProfileController(MyProfileService myProfileService,
                               OutboxService outboxService) {
        this.myProfileService = myProfileService;
        this.outboxService = outboxService;
    }

    @GetMapping
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<MyProfileResponse> me(@AuthenticationPrincipal UserPrincipal principal) {
        UUID userId = principal.getId();
        MyProfileResponse resp = myProfileService.getProfile(userId);
        outboxService.publish("lab.audit.events",
                Map.of("event", "PROFILE_VIEWED",
                        "user_id", userId.toString(),
                        "username", principal.getUsername()));
        return ResponseEntity.ok(resp);
    }

    @PatchMapping
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<MyProfileResponse> update(@AuthenticationPrincipal UserPrincipal principal,
                                                    @Valid @RequestBody UpdateMyProfileRequest req) {
        UUID userId = principal.getId();
        MyProfileResponse resp = myProfileService.updateProfile(userId, req);
        outboxService.publish("lab.audit.events",
                Map.of("event", "PROFILE_UPDATED",
                        "user_id", userId.toString(),
                        "username", principal.getUsername()));
        return ResponseEntity.ok(resp);
    }

    @PutMapping
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<MyProfileResponse> updatePut(@AuthenticationPrincipal UserPrincipal principal,
                                                       @Valid @RequestBody UpdateMyProfileRequest req) {
        UUID userId = principal.getId();
        MyProfileResponse resp = myProfileService.updateProfile(userId, req);
        outboxService.publish("lab.audit.events",
                Map.of("event", "PROFILE_UPDATED",
                        "user_id", userId.toString(),
                        "username", principal.getUsername()));
        return ResponseEntity.ok(resp);
    }

    @PostMapping("/change-password")
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<?> changePassword(@AuthenticationPrincipal UserPrincipal principal,
                                            @Valid @RequestBody ChangePasswordRequest req) {
        UUID userId = principal.getId();
        myProfileService.changePassword(userId, req);
        outboxService.publish("lab.audit.events",
                Map.of("event", "PROFILE_PASSWORD_CHANGED",
                        "user_id", userId.toString(),
                        "username", principal.getUsername()));
        return ResponseEntity.ok().build();
    }

    @PostMapping("/change-password-first-login")
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<?> changePasswordFirstLogin(
            @AuthenticationPrincipal UserPrincipal principal,
            @Valid @RequestBody ChangePasswordFirstLoginRequest req) {
        UUID userId = principal.getId();
        myProfileService.changePasswordFirstLogin(userId, req);
        outboxService.publish("lab.audit.events",
                Map.of("event", "PROFILE_FIRST_LOGIN_PASSWORD_CHANGED",
                        "user_id", userId.toString(),
                        "username", principal.getUsername()));
        return ResponseEntity.ok(Map.of("message", "Password changed successfully"));
    }
}
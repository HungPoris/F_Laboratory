package fpt.com.laboratorymanagementbackend.internal.controller;

import fpt.com.laboratorymanagementbackend.domain.iam.user.repository.UserRepository;
import fpt.com.laboratorymanagementbackend.internal.dto.InternalJwtVerifyRequest;
import fpt.com.laboratorymanagementbackend.internal.dto.InternalJwtVerifyResponse;
import fpt.com.laboratorymanagementbackend.internal.dto.InternalUserSummaryResponse;
import fpt.com.laboratorymanagementbackend.internal.service.InternalJwtService;
import fpt.com.laboratorymanagementbackend.domain.iam.user.entity.User;
import fpt.com.laboratorymanagementbackend.domain.iam.user.repository.UserRepository;
import fpt.com.laboratorymanagementbackend.internal.dto.InternalUserSummaryResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.UUID;
import java.util.stream.Collectors;
@Slf4j
@RestController
@RequestMapping("/internal/security")
@RequiredArgsConstructor
public class InternalSecurityController {

    private final InternalJwtService internalJwtService;
    private final UserRepository userRepository;

    @GetMapping("/verify")
    public ResponseEntity<String> verify() {
        return ResponseEntity.ok("OK");
    }

    @PostMapping("/jwt/verify")
    public ResponseEntity<InternalJwtVerifyResponse> verifyJwt(
            @RequestBody InternalJwtVerifyRequest request
    ) {
        log.debug("Received JWT verification request");

        InternalJwtVerifyResponse response = internalJwtService.verifyToken(request);

        if (!response.isValid()) {
            log.warn("JWT verification failed: {}", response.getErrorMessage());
            return ResponseEntity.status(401).body(response);
        }

        log.info("JWT verified successfully for userId: {}", response.getUserId());
        return ResponseEntity.ok(response);
    }
    @PostMapping("/users/batch-fetch")
    public ResponseEntity<List<InternalUserSummaryResponse>> getUsersByIds(@RequestBody List<UUID> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return ResponseEntity.ok(List.of());
        }

        List<User> users = userRepository.findAllById(userIds);

        List<InternalUserSummaryResponse> response = users.stream()
                .map(u -> InternalUserSummaryResponse.builder()
                        .userId(u.getUserId())
                        .username(u.getUsername())
                        .fullName(u.getFullName())
                        .build())
                .collect(Collectors.toList());

        return ResponseEntity.ok(response);
    }

}
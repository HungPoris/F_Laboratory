package fpt.com.laboratorymanagementbackend.domain.iam.profile.service;

import fpt.com.laboratorymanagementbackend.domain.iam.profile.dto.MyProfileResponse;
import fpt.com.laboratorymanagementbackend.domain.iam.profile.dto.UpdateMyProfileRequest;
import fpt.com.laboratorymanagementbackend.domain.iam.profile.dto.ChangePasswordRequest;
import fpt.com.laboratorymanagementbackend.domain.iam.auth.dto.ChangePasswordFirstLoginRequest;
import fpt.com.laboratorymanagementbackend.domain.iam.user.entity.User;
import fpt.com.laboratorymanagementbackend.domain.iam.user.repository.UserRepository;
import fpt.com.laboratorymanagementbackend.common.service.JwtBlacklistService;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.UUID;

@Service
public class MyProfileService {
    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtBlacklistService jwtBlacklistService;

    public MyProfileService(UserRepository userRepository, PasswordEncoder passwordEncoder, JwtBlacklistService jwtBlacklistService) {
        this.userRepository = userRepository;
        this.passwordEncoder = passwordEncoder;
        this.jwtBlacklistService = jwtBlacklistService;
    }

    public MyProfileResponse getProfile(UUID userId) {
        User u = userRepository.findById(userId).orElseThrow(() -> new IllegalArgumentException("USER_NOT_FOUND"));
        MyProfileResponse r = new MyProfileResponse();
        r.setUserId(u.getUserId().toString());
        r.setUsername(u.getUsername());
        r.setFullName(u.getFullName());
        r.setEmail(u.getEmail());
        r.setPhoneNumber(u.getPhoneNumber());
        r.setDateOfBirth(u.getDateOfBirth());
        r.setIdentityNumber(u.getIdentityNumber());
        r.setGender(u.getGender());
        r.setAddress(u.getAddress());
        return r;
    }

    @Transactional
    public MyProfileResponse updateProfile(UUID userId, UpdateMyProfileRequest req) {
        User u = userRepository.findById(userId).orElseThrow(() -> new IllegalArgumentException("USER_NOT_FOUND"));

        if (req.getFullName() != null) u.setFullName(req.getFullName().trim());
        if (req.getPhoneNumber() != null) u.setPhoneNumber(req.getPhoneNumber().trim());
        if (req.getDateOfBirth() != null) u.setDateOfBirth(req.getDateOfBirth());
        if (req.getIdentityNumber() != null) u.setIdentityNumber(req.getIdentityNumber().trim());
        if (req.getGender() != null) u.setGender(req.getGender());
        if (req.getAddress() != null) u.setAddress(req.getAddress());

        u.setUpdatedAt(OffsetDateTime.now());
        userRepository.save(u);

        return getProfile(userId);
    }

    @Transactional
    public void changePassword(UUID userId, ChangePasswordRequest req) {
        User u = userRepository.findById(userId).orElseThrow(() -> new IllegalArgumentException("USER_NOT_FOUND"));

        String current = req.getCurrentPassword();
        String next = req.getNewPassword();

        if (current == null || !passwordEncoder.matches(current, u.getPasswordHash())) {
            throw new IllegalArgumentException("INVALID_CURRENT_PASSWORD");
        }
        if (next == null || next.length() < 8 || next.length() > 128) {
            throw new IllegalArgumentException("WEAK_PASSWORD");
        }
        if (passwordEncoder.matches(next, u.getPasswordHash())) {
            throw new IllegalArgumentException("PASSWORD_SAME_AS_OLD");
        }

        u.setPasswordHash(passwordEncoder.encode(next));
        u.setPasswordUpdatedAt(OffsetDateTime.now());
        u.setMustChangePassword(false);
        u.setUpdatedAt(OffsetDateTime.now());
        userRepository.save(u);

        jwtBlacklistService.blacklistAllTokensForUser(userId.toString());
    }

    @Transactional
    public void changePasswordFirstLogin(UUID userId, ChangePasswordFirstLoginRequest req) {
        User u = userRepository.findById(userId)
                .orElseThrow(() -> new IllegalArgumentException("USER_NOT_FOUND"));

        if (!req.getNewPassword().equals(req.getConfirmPassword())) {
            throw new IllegalArgumentException("PASSWORD_MISMATCH");
        }

        String current = req.getCurrentPassword();
        String next = req.getNewPassword();

        if (current == null || !passwordEncoder.matches(current, u.getPasswordHash())) {
            throw new IllegalArgumentException("INVALID_CURRENT_PASSWORD");
        }

        if (next == null || next.length() < 8 || next.length() > 128) {
            throw new IllegalArgumentException("WEAK_PASSWORD");
        }

        if (!next.matches("^(?=.*[a-z])(?=.*[A-Z])(?=.*\\d).*$")) {
            throw new IllegalArgumentException("WEAK_PASSWORD");
        }

        if (passwordEncoder.matches(next, u.getPasswordHash())) {
            throw new IllegalArgumentException("PASSWORD_SAME_AS_OLD");
        }

        u.setPasswordHash(passwordEncoder.encode(next));
        u.setPasswordUpdatedAt(OffsetDateTime.now());
        u.setMustChangePassword(false);
        u.setUpdatedAt(OffsetDateTime.now());
        userRepository.save(u);

        jwtBlacklistService.blacklistAllTokensForUser(userId.toString());
    }
}
package fpt.com.laboratorymanagementbackend.domain.iam.user.service;

import fpt.com.laboratorymanagementbackend.common.service.EmailService;
import fpt.com.laboratorymanagementbackend.common.service.OutboxService;
import fpt.com.laboratorymanagementbackend.domain.iam.role.entity.Role;
import fpt.com.laboratorymanagementbackend.domain.iam.role.repository.PrivilegeRepository;
import fpt.com.laboratorymanagementbackend.domain.iam.role.repository.RoleRepository;
import fpt.com.laboratorymanagementbackend.domain.iam.user.dto.CreateUserAdminDto;
import fpt.com.laboratorymanagementbackend.domain.iam.user.dto.UpdateUserAdminDto;
import fpt.com.laboratorymanagementbackend.domain.iam.user.dto.UserAdminDto;
import fpt.com.laboratorymanagementbackend.domain.iam.user.entity.User;
import fpt.com.laboratorymanagementbackend.domain.iam.user.repository.UserRepository;
import fpt.com.laboratorymanagementbackend.security.failedlogin.FailedLoginService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.security.SecureRandom;
import java.text.Normalizer;
import java.time.OffsetDateTime;
import java.util.*;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

@Service
public class AdminUserService {

    private static final Logger log = LoggerFactory.getLogger(AdminUserService.class);

    private final UserRepository userRepository;
    private final RoleRepository roleRepository;
    private final PrivilegeRepository privilegeRepository;
    private final PasswordEncoder passwordEncoder;
    private final OutboxService outboxService;
    private final EmailService emailService;
    private final RabbitTemplate rabbitTemplate;
    private final FailedLoginService failedLoginService;

    public AdminUserService(UserRepository userRepository,
                            RoleRepository roleRepository,
                            PrivilegeRepository privilegeRepository,
                            PasswordEncoder passwordEncoder,
                            OutboxService outboxService,
                            RabbitTemplate rabbitTemplate,
                            EmailService emailService,
                            FailedLoginService failedLoginService) {
        this.userRepository = userRepository;
        this.roleRepository = roleRepository;
        this.privilegeRepository = privilegeRepository;
        this.passwordEncoder = passwordEncoder;
        this.outboxService = outboxService;
        this.rabbitTemplate = rabbitTemplate;
        this.emailService = emailService;
        this.failedLoginService = failedLoginService;
    }

    private UUID getCurrentUserId() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !auth.isAuthenticated()) return null;
        String name = auth.getName();
        if (name == null) return null;
        return userRepository.findByUsernameIgnoreCaseOrEmailIgnoreCase(name, name)
                .map(User::getUserId)
                .orElse(null);
    }

    private void checkNotSelf(UUID targetUserId, String operation) {
        UUID currentUserId = getCurrentUserId();
        if (currentUserId != null && currentUserId.equals(targetUserId)) {
            throw new IllegalArgumentException("CANNOT_" + operation.toUpperCase() + "_YOURSELF");
        }
    }

    @Transactional
    public Map<String, Object> createUserByAdminWithOptionalPassword(CreateUserAdminDto dto) {
        if (dto.getEmail() == null || dto.getEmail().isBlank()
                || dto.getFullName() == null || dto.getFullName().isBlank()) {
            throw new IllegalArgumentException("VALIDATION_FAILED");
        }

        if (dto.getUsername() != null) dto.setUsername(dto.getUsername().trim());
        if (dto.getEmail() != null) dto.setEmail(dto.getEmail().trim().toLowerCase());
        if (dto.getFullName() != null) dto.setFullName(dto.getFullName().trim());
        if (dto.getPhoneNumber() != null) dto.setPhoneNumber(dto.getPhoneNumber().trim());
        if (dto.getIdentityNumber() != null) dto.setIdentityNumber(dto.getIdentityNumber().trim());

        if (dto.getUsername() != null && !dto.getUsername().isBlank()) {
            if (userRepository.existsByUsernameIgnoreCase(dto.getUsername())) throw new IllegalArgumentException("USERNAME_EXISTS");
        }
        if (userRepository.existsByEmailIgnoreCase(dto.getEmail())) throw new IllegalArgumentException("EMAIL_EXISTS");

        boolean generated = false;
        String plain = dto.getPassword();
        if (plain == null || plain.isBlank()) {
            plain = generateRandomPassword8();
            generated = true;
        }

        String finalUsername;
        if (dto.getUsername() != null && !dto.getUsername().isBlank()) {
            finalUsername = dto.getUsername();
        } else {
            finalUsername = generateUsernameFromFullName(dto.getFullName());
            finalUsername = ensureUniqueUsername(finalUsername);
        }

        User u = new User();
        u.setUserId(UUID.randomUUID());
        u.setUsername(finalUsername);
        u.setEmail(dto.getEmail());
        u.setFullName(dto.getFullName());
        u.setPhoneNumber(dto.getPhoneNumber());
        u.setDateOfBirth(dto.getDateOfBirth());
        u.setAddress(dto.getAddress());
        u.setIdentityNumber(dto.getIdentityNumber());
        u.setGender(dto.getGender());
        u.setIsActive(true);
        u.setIsLocked(false);
        u.setMustChangePassword(generated);
        u.setFailedLoginAttempts(0);
        u.setCreatedAt(OffsetDateTime.now());
        u.setUpdatedAt(OffsetDateTime.now());
        u.setPasswordAlgorithm("ARGON2ID");
        u.setPasswordUpdatedAt(OffsetDateTime.now());
        u.setPasswordHash(passwordEncoder.encode(plain));

        Set<Role> roles = new HashSet<>();
        if (dto.getRoles() != null && !dto.getRoles().isEmpty()) {
            roles = dto.getRoles().stream()
                    .filter(Objects::nonNull)
                    .map(String::trim)
                    .map(String::toUpperCase)
                    .map(roleRepository::findByRoleCode)
                    .filter(Optional::isPresent)
                    .map(Optional::get)
                    .collect(Collectors.toSet());
        }
        if (roles.isEmpty()) {
            roleRepository.findByRoleCode("USER").ifPresent(roles::add);
        }
        u.setRoles(roles);

        User saved = userRepository.save(u);

        try {
            Map<String, Object> modelInner = new HashMap<>();
            modelInner.put("username", saved.getUsername());
            modelInner.put("fullName", saved.getFullName());
            if (generated) modelInner.put("password", plain);
            Map<String, Object> vars = Map.of("model", modelInner);
            Map<String, Object> payload = new HashMap<>();
            payload.put("template", "welcome");
            payload.put("to", Map.of("email", saved.getEmail()));
            payload.put("variables", vars);
            payload.put("subject", "Welcome");
            outboxService.publish("lab.notify.queue", payload);
        } catch (Exception ex) {
            log.warn("Failed to enqueue welcome email for user {}: {}", saved.getUserId(), ex.getMessage());
        }

        try {
            outboxService.publish("lab.audit.events", Map.of(
                    "event", "USER_CREATED_BY_ADMIN",
                    "user_id", saved.getUserId().toString(),
                    "username", saved.getUsername()
            ));
        } catch (Exception ex) {
            log.warn("Failed to publish audit event for user {}: {}", saved.getUserId(), ex.getMessage());
        }

        Map<String, Object> result = new HashMap<>();
        result.put("user", saved);
        if (generated) result.put("password", plain);
        return result;
    }

    @Transactional(readOnly = true)
    public Page<UserAdminDto> list(Pageable pageable, String q, String status, String role) {

        Page<User> users = userRepository.searchWithFilters(q, status, role, pageable);


        return users.map(user -> {
            user.getRoles().size();
            return toDto(user);
        });
    }

    @Transactional(readOnly = true)
    public UserAdminDto get(UUID id) {
        User u = userRepository.findById(id).orElseThrow(() -> new IllegalArgumentException("USER_NOT_FOUND"));
        return toDto(u);
    }

    @Transactional
    public UserAdminDto update(UUID id, UpdateUserAdminDto dto) {
        User u = userRepository.findById(id).orElseThrow(() -> new IllegalArgumentException("USER_NOT_FOUND"));
        if (dto.getFullName() != null) u.setFullName(dto.getFullName().trim());
        if (dto.getEmail() != null && !dto.getEmail().equalsIgnoreCase(u.getEmail())) {
            String emailNorm = dto.getEmail().trim().toLowerCase();
            if (userRepository.existsByEmailIgnoreCase(emailNorm)) throw new IllegalArgumentException("EMAIL_EXISTS");
            u.setEmail(emailNorm);
        }
        if (dto.getPhoneNumber() != null) u.setPhoneNumber(dto.getPhoneNumber().trim());
        if (dto.getDateOfBirth() != null) u.setDateOfBirth(dto.getDateOfBirth());
        if (dto.getAddress() != null) u.setAddress(dto.getAddress());
        if (dto.getIdentityNumber() != null) u.setIdentityNumber(dto.getIdentityNumber().trim());
        if (dto.getGender() != null) u.setGender(dto.getGender());
        if (dto.getIsActive() != null) u.setIsActive(dto.getIsActive());
        if (dto.getIsLocked() != null) u.setIsLocked(dto.getIsLocked());
        if (dto.getNewPassword() != null && !dto.getNewPassword().isBlank()) {
            u.setPasswordHash(passwordEncoder.encode(dto.getNewPassword()));
            u.setMustChangePassword(false);
            u.setPasswordUpdatedAt(OffsetDateTime.now());
        }
        if (dto.getRoles() != null) {
            Set<Role> newRoles = dto.getRoles().stream()
                    .filter(Objects::nonNull)
                    .map(String::trim)
                    .map(String::toUpperCase)
                    .map(roleRepository::findByRoleCode)
                    .filter(Optional::isPresent)
                    .map(Optional::get)
                    .collect(Collectors.toSet());
            u.setRoles(newRoles);
        }
        u.setUpdatedAt(OffsetDateTime.now());
        User saved = userRepository.save(u);
        try {
            outboxService.publish("lab.audit.events", Map.of(
                    "event", "USER_UPDATED",
                    "user_id", saved.getUserId().toString()
            ));
        } catch (Exception ignored) {}
        return toDto(saved);
    }

    @Transactional
    public void deleteUser(UUID id) {
        checkNotSelf(id, "delete");
        User u = userRepository.findById(id).orElseThrow(() -> new IllegalArgumentException("USER_NOT_FOUND"));
        userRepository.delete(u);
        outboxService.publish("lab.audit.events", Map.of(
                "event", "USER_DELETED",
                "user_id", id.toString(),
                "username", u.getUsername()
        ));
    }

    @Transactional
    public void lock(UUID id) {
        checkNotSelf(id, "lock");
        User u = userRepository.findById(id).orElseThrow(() -> new IllegalArgumentException("USER_NOT_FOUND"));
        u.setIsLocked(true);
        u.setLockedAt(OffsetDateTime.now());
        u.setLockedUntil(null);
        u.setUpdatedAt(OffsetDateTime.now());
        userRepository.save(u);
        outboxService.publish("lab.audit.events", Map.of(
                "event", "USER_LOCKED",
                "user_id", id.toString(),
                "mode", "ADMIN_ONLY"
        ));
    }

    @Transactional
    public void unlock(UUID id) {
        failedLoginService.clearLock(id);
    }

    @Transactional
    public void ban(UUID id, String reason) {
        checkNotSelf(id, "ban");
        User u = userRepository.findById(id).orElseThrow(() -> new IllegalArgumentException("USER_NOT_FOUND"));
        u.setIsActive(false);
        u.setLockedReason(reason);
        u.setUpdatedAt(OffsetDateTime.now());
        userRepository.save(u);
        outboxService.publish("lab.audit.events", Map.of(
                "event", "USER_BANNED",
                "user_id", id.toString(),
                "reason", reason == null ? "" : reason
        ));
    }

    @Transactional
    public void unban(UUID id) {
        User u = userRepository.findById(id).orElseThrow(() -> new IllegalArgumentException("USER_NOT_FOUND"));
        u.setIsActive(true);
        u.setLockedReason(null);
        u.setIsLocked(false);
        u.setLockedAt(null);
        u.setLockedUntil(null);
        u.setFailedLoginAttempts(0);
        u.setUpdatedAt(OffsetDateTime.now());
        userRepository.save(u);
        outboxService.publish("lab.audit.events", Map.of(
                "event", "USER_UNBANNED",
                "user_id", id.toString()
        ));
    }

    @Transactional
    public void assignRole(UUID userId, String roleCode) {
        checkNotSelf(userId, "change_roles");
        User u = userRepository.findById(userId).orElseThrow(() -> new IllegalArgumentException("USER_NOT_FOUND"));
        Role r = roleRepository.findByRoleCode(roleCode).orElseThrow(() -> new IllegalArgumentException("ROLE_NOT_FOUND"));
        if (u.getRoles() == null) u.setRoles(new HashSet<>());
        boolean already = u.getRoles().stream().anyMatch(rr -> rr.getRoleCode().equals(r.getRoleCode()));
        if (!already) {
            u.getRoles().add(r);
            u.setUpdatedAt(OffsetDateTime.now());
            userRepository.save(u);
            outboxService.publish("lab.audit.events", Map.of(
                    "event", "USER_ROLE_ASSIGNED",
                    "user_id", userId.toString(),
                    "role_code", r.getRoleCode()
            ));
        }
    }

    @Transactional
    public void sendWelcome(UUID userId, String optionalPassword) {
        User saved = userRepository.findById(userId).orElseThrow(() -> new IllegalArgumentException("USER_NOT_FOUND"));
        try {
            Map<String, Object> modelInner = new HashMap<>();
            modelInner.put("username", saved.getUsername());
            modelInner.put("fullName", saved.getFullName());
            if (optionalPassword != null && !optionalPassword.isBlank()) {
                modelInner.put("password", optionalPassword);
            }
            try {
                emailService.sendHtml(saved.getEmail(), "Welcome", "welcome", modelInner);
            } catch (Exception directEx) {
                log.warn("Direct welcome email send failed for user {}: {}", saved.getUserId(), directEx.getMessage());
            }
            Map<String, Object> vars = Map.of("model", modelInner);
            Map<String, Object> payload = new HashMap<>();
            payload.put("template", "welcome");
            payload.put("to", Map.of("email", saved.getEmail()));
            payload.put("variables", vars);
            payload.put("subject", "Welcome");
            try {
                rabbitTemplate.convertAndSend("lab.notify.exchange", "notify.welcome.send", payload);
            } catch (Exception e1) {
                try {
                    rabbitTemplate.convertAndSend("", "lab.notify.queue", payload);
                } catch (Exception e2) {
                    outboxService.publish("lab.notify.queue", payload);
                }
            }
        } catch (Exception ex) {
            log.warn("Failed to dispatch welcome email for user {}: {}", saved.getUserId(), ex.getMessage());
        }
    }

    private String ensureUniqueUsername(String base) {
        String candidate = base;
        int suffix = 1;
        while (userRepository.existsByUsernameIgnoreCase(candidate)) {
            candidate = base + suffix;
            suffix++;
        }
        return candidate;
    }

    private String generateUsernameFromFullName(String fullName) {
        if (fullName == null || fullName.trim().isEmpty()) {
            return "user" + UUID.randomUUID().toString().replace("-", "").substring(0, 6);
        }
        String[] parts = fullName.trim().split("\\s+");
        if (parts.length == 0) {
            return "user" + UUID.randomUUID().toString().replace("-", "").substring(0, 6);
        }
        String given = parts[parts.length - 1];
        StringBuilder initials = new StringBuilder();
        for (int i = 0; i < parts.length - 1; i++) {
            String p = parts[i];
            if (p != null && !p.isBlank()) {
                char c = p.trim().charAt(0);
                String s = String.valueOf(c);
                s = removeDiacritics(s);
                if (!s.isBlank()) initials.append(s.toUpperCase());
            }
        }
        String givenNorm = removeDiacritics(given).replaceAll("[^A-Za-z0-9]", "");
        if (givenNorm.isBlank()) {
            givenNorm = "user" + UUID.randomUUID().toString().replace("-", "").substring(0, 4);
        } else {
            givenNorm = capitalize(givenNorm);
        }
        return givenNorm + initials.toString();
    }

    private String capitalize(String s) {
        if (s == null || s.isEmpty()) return s;
        if (s.length() == 1) return s.toUpperCase();
        return s.substring(0,1).toUpperCase() + s.substring(1);
    }

    private String removeDiacritics(String s) {
        if (s == null) return null;
        String normalized = Normalizer.normalize(s, Normalizer.Form.NFD);
        Pattern pattern = Pattern.compile("\\p{InCombiningDiacriticalMarks}+");
        return pattern.matcher(normalized).replaceAll("");
    }

    private String generateRandomPassword8() {
        SecureRandom rnd = new SecureRandom();
        String upper = "ABCDEFGHJKLMNPQRSTUVWXYZ";
        String lower = "abcdefghijkmnpqrstuvwxyz";
        String digits = "0123456789";
        String special = "!@#$%&*()-_=+[]{}<>?";
        String all = upper + lower + digits + special;
        char[] pwd = new char[8];
        pwd[0] = upper.charAt(rnd.nextInt(upper.length()));
        pwd[1] = lower.charAt(rnd.nextInt(lower.length()));
        pwd[2] = digits.charAt(rnd.nextInt(digits.length()));
        pwd[3] = special.charAt(rnd.nextInt(special.length()));
        for (int i = 4; i < 8; i++) pwd[i] = all.charAt(rnd.nextInt(all.length()));
        for (int i = pwd.length - 1; i > 0; i--) {
            int j = rnd.nextInt(i + 1);
            char tmp = pwd[i];
            pwd[i] = pwd[j];
            pwd[j] = tmp;
        }
        return new String(pwd);
    }

    private UserAdminDto toDto(User u) {
        UserAdminDto d = new UserAdminDto();
        d.setUserId(u.getUserId());
        d.setUsername(u.getUsername());
        d.setEmail(u.getEmail());
        d.setFullName(u.getFullName());
        d.setPhoneNumber(u.getPhoneNumber());
        d.setDateOfBirth(u.getDateOfBirth());
        d.setAddress(u.getAddress());
        d.setIdentityNumber(u.getIdentityNumber());
        d.setGender(u.getGender());
        d.setIsActive(u.getIsActive());
        d.setIsLocked(u.getIsLocked());
        d.setFailedLoginAttempts(u.getFailedLoginAttempts());
        d.setCreatedAt(u.getCreatedAt());
        d.setRoles(
                u.getRoles() == null
                        ? Collections.emptySet()
                        : u.getRoles().stream().map(Role::getRoleCode).collect(Collectors.toSet())
        );
        return d;
    }

    @Transactional
    public void resetPasswordAndEmail(UUID userId) {
        User u = userRepository.findById(userId)
                .orElseThrow(() -> new IllegalArgumentException("USER_NOT_FOUND"));

        String toEmail = u.getEmail();
        if (toEmail == null || toEmail.isBlank()) {
            throw new IllegalStateException("USER_MISSING_EMAIL");
        }

        String temp = generateRandomPassword8();
        u.setPasswordHash(passwordEncoder.encode(temp));
        u.setPasswordUpdatedAt(OffsetDateTime.now());
        u.setMustChangePassword(true);
        userRepository.save(u);

        Map<String, Object> model = new HashMap<>();
        if (u.getFullName() != null && !u.getFullName().isBlank()) model.put("fullName", u.getFullName());
        if (u.getUsername() != null && !u.getUsername().isBlank()) model.put("username", u.getUsername());
        model.put("password", temp);

        Map<String, Object> variables = new HashMap<>();
        variables.put("model", model);
        try {
            emailService.sendHtml(toEmail, "Reset your password", "reset-password", variables);
        } catch (Exception ignored) {}

        try {
            Map<String, Object> to = new HashMap<>();
            to.put("email", toEmail);
            Map<String, Object> payload = new HashMap<>();
            payload.put("template", "reset-password");
            payload.put("to", to);
            payload.put("variables", variables);
            payload.put("subject", "Reset your password");
            try {
                rabbitTemplate.convertAndSend("lab.notify.exchange", "notify.reset.send", payload);
            } catch (Exception e1) {
                try {
                    rabbitTemplate.convertAndSend("", "lab.notify.queue", payload);
                } catch (Exception e2) {
                    outboxService.publish("lab.notify.queue", payload);
                }
            }
        } catch (Exception ignored) {}
    }
}
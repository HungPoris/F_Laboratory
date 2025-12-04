package fpt.com.laboratorymanagementbackend.domain.iam.user.controller;

import fpt.com.laboratorymanagementbackend.domain.iam.user.dto.CreateUserAdminDto;
import fpt.com.laboratorymanagementbackend.domain.iam.user.dto.UpdateUserAdminDto;
import fpt.com.laboratorymanagementbackend.domain.iam.user.dto.UserAdminDto;
import fpt.com.laboratorymanagementbackend.domain.iam.user.entity.User;
import fpt.com.laboratorymanagementbackend.domain.iam.user.service.AdminUserService;
import fpt.com.laboratorymanagementbackend.common.service.OutboxService;
import jakarta.validation.Valid;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/admin")
public class UserAdminController {

    private static final Logger log = LoggerFactory.getLogger(UserAdminController.class);

    private final AdminUserService adminUserService;
    private final OutboxService outboxService;

    public UserAdminController(AdminUserService adminUserService,
                               OutboxService outboxService) {
        this.adminUserService = adminUserService;
        this.outboxService = outboxService;
    }

    @PreAuthorize("hasAuthority('user.view') or hasRole('ADMIN')")
    @GetMapping("/users")
    public ResponseEntity<Page<UserAdminDto>> list(
            Pageable pageable,
            @RequestParam(name = "q", required = false) String q,
            @RequestParam(name = "status", required = false) String status,
            @RequestParam(name = "role", required = false) String role) {

        Page<UserAdminDto> result = adminUserService.list(pageable, q, status, role);

        outboxService.publish("lab.audit.events",
                Map.of("event", "ADMIN_USERS_LIST",
                        "page", String.valueOf(pageable.getPageNumber()),
                        "size", String.valueOf(pageable.getPageSize()),
                        "q", q == null ? "" : q,
                        "status", status == null ? "all" : status,
                        "role", role == null ? "" : role));

        return ResponseEntity.ok(result);
    }

    @PreAuthorize("hasAuthority('user.view') or hasRole('ADMIN')")
    @GetMapping("/users/{id}")
    public ResponseEntity<UserAdminDto> get(@PathVariable UUID id) {
        UserAdminDto dto = adminUserService.get(id);
        outboxService.publish("lab.audit.events",
                Map.of("event", "ADMIN_USER_GET",
                        "user_id", id.toString(),
                        "username", dto.getUsername() == null ? "" : dto.getUsername()));
        return ResponseEntity.ok(dto);
    }

    @PreAuthorize("hasAuthority('user.create') or hasRole('ADMIN')")
    @PostMapping("/users")
    public ResponseEntity<?> createUser(@Valid @RequestBody CreateUserAdminDto dto,
                                        @RequestParam(name = "revealPassword", required = false, defaultValue = "false") boolean revealPassword) {
        Map<String, Object> res = adminUserService.createUserByAdminWithOptionalPassword(dto);
        User u = (User) res.get("user");
        String pwd = (String) res.get("password");

        outboxService.publish("lab.audit.events",
                Map.of("event", "ADMIN_USER_CREATE",
                        "user_id", u.getUserId().toString(),
                        "username", u.getUsername()));

        if (revealPassword && pwd != null) {
            return ResponseEntity.ok(Map.of("id", u.getUserId(), "password", pwd));
        } else {
            return ResponseEntity.ok(Map.of("id", u.getUserId()));
        }
    }

    @PreAuthorize("hasAuthority('user.modify') or hasRole('ADMIN')")
    @PutMapping("/users/{id}")
    public ResponseEntity<UserAdminDto> update(@PathVariable UUID id, @Valid @RequestBody UpdateUserAdminDto dto) {
        UserAdminDto updated = adminUserService.update(id, dto);
        outboxService.publish("lab.audit.events",
                Map.of("event", "ADMIN_USER_UPDATE",
                        "user_id", id.toString(),
                        "username", updated.getUsername() == null ? "" : updated.getUsername()));
        return ResponseEntity.ok(updated);
    }

    @PreAuthorize("hasAuthority('user.delete') or hasRole('ADMIN')")
    @DeleteMapping("/users/{id}")
    public ResponseEntity<?> deleteUser(@PathVariable UUID id) {
        adminUserService.deleteUser(id);
        outboxService.publish("lab.audit.events",
                Map.of("event", "ADMIN_USER_DELETE",
                        "user_id", id.toString()));
        return ResponseEntity.noContent().build();
    }

    @PreAuthorize("hasAuthority('user.lock_unlock') or hasRole('ADMIN')")
    @PostMapping("/users/{id}/lock")
    public ResponseEntity<?> lock(@PathVariable UUID id) {
        adminUserService.lock(id);
        outboxService.publish("lab.audit.events",
                Map.of("event", "ADMIN_USER_LOCK",
                        "user_id", id.toString()));
        return ResponseEntity.ok().build();
    }

    @PreAuthorize("hasAuthority('user.lock_unlock') or hasRole('ADMIN')")
    @PostMapping("/users/{id}/unlock")
    public ResponseEntity<?> unlock(@PathVariable UUID id) {
        adminUserService.unlock(id);
        outboxService.publish("lab.audit.events",
                Map.of("event", "ADMIN_USER_UNLOCK",
                        "user_id", id.toString()));
        return ResponseEntity.ok().build();
    }

    @PreAuthorize("hasAuthority('user.ban_unban') or hasRole('ADMIN')")
    @PostMapping("/users/{id}/ban")
    public ResponseEntity<?> ban(@PathVariable UUID id, @RequestParam(required = false) String reason) {
        adminUserService.ban(id, reason);
        if (reason != null && !reason.isBlank()) {
            outboxService.publish("lab.audit.events",
                    Map.of("event", "ADMIN_USER_BAN",
                            "user_id", id.toString(),
                            "reason", reason));
        } else {
            outboxService.publish("lab.audit.events",
                    Map.of("event", "ADMIN_USER_BAN",
                            "user_id", id.toString()));
        }
        return ResponseEntity.ok().build();
    }

    @PreAuthorize("hasAuthority('user.ban_unban') or hasRole('ADMIN')")
    @PostMapping("/users/{id}/unban")
    public ResponseEntity<?> unban(@PathVariable UUID id) {
        adminUserService.unban(id);
        outboxService.publish("lab.audit.events",
                Map.of("event", "ADMIN_USER_UNBAN",
                        "user_id", id.toString()));
        return ResponseEntity.ok().build();
    }

    @PreAuthorize("hasAuthority('user.modify') or hasRole('ADMIN')")
    @PostMapping("/users/{id}/roles")
    public ResponseEntity<?> assignRole(@PathVariable UUID id, @RequestParam String roleCode) {
        adminUserService.assignRole(id, roleCode);
        outboxService.publish("lab.audit.events",
                Map.of("event", "ADMIN_USER_ROLE_ASSIGN",
                        "user_id", id.toString(),
                        "role_code", roleCode));
        return ResponseEntity.ok().build();
    }

    @PreAuthorize("hasAuthority('user.create') or hasRole('ADMIN')")
    @PostMapping("/users/{id}/welcome")
    public ResponseEntity<?> sendWelcome(@PathVariable UUID id, @RequestBody(required = false) Map<String, Object> body) {
        String pwd = null;
        if (body != null && body.get("password") != null) {
            pwd = String.valueOf(body.get("password"));
        }
        adminUserService.sendWelcome(id, pwd);
        outboxService.publish("lab.audit.events",
                Map.of("event", "ADMIN_USER_WELCOME",
                        "user_id", id.toString()));
        return ResponseEntity.accepted().build();
    }

    @PreAuthorize("hasAuthority('user.modify') or hasRole('ADMIN')")
    @PostMapping("/users/{id}/reset-password")
    public ResponseEntity<?> resetPassword(@PathVariable UUID id) {
        adminUserService.resetPasswordAndEmail(id);
        outboxService.publish("lab.audit.events",
                Map.of("event", "ADMIN_USER_RESET_PASSWORD",
                        "user_id", id.toString()));
        return ResponseEntity.accepted().build();
    }
}

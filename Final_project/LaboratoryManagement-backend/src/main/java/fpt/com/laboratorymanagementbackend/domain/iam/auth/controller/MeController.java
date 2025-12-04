package fpt.com.laboratorymanagementbackend.domain.iam.auth.controller;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import fpt.com.laboratorymanagementbackend.domain.iam.auth.dto.MeResponse;
import fpt.com.laboratorymanagementbackend.domain.iam.auth.dto.ScreenDto;
import fpt.com.laboratorymanagementbackend.domain.iam.role.entity.Privilege;
import fpt.com.laboratorymanagementbackend.domain.iam.role.entity.Role;
import fpt.com.laboratorymanagementbackend.domain.iam.user.entity.User;
import fpt.com.laboratorymanagementbackend.domain.iam.user.repository.UserRepository;
import fpt.com.laboratorymanagementbackend.domain.iam.screen.service.UiAccessService;
import fpt.com.laboratorymanagementbackend.security.userdetails.UserPrincipal;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.*;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/v1/auth")
public class MeController {

    private final UserRepository userRepository;
    private final UiAccessService uiAccessService;
    private final ObjectMapper objectMapper;

    public MeController(UserRepository userRepository, UiAccessService uiAccessService, ObjectMapper objectMapper) {
        this.userRepository = userRepository;
        this.uiAccessService = uiAccessService;
        this.objectMapper = objectMapper;
    }

    @GetMapping("/me")
    public ResponseEntity<MeResponse> me(@AuthenticationPrincipal Object principalObj) {
        if (principalObj == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }

        String userId = null;
        String username = null;
        String email = null;
        String fullName = null;
        Set<String> roles = new HashSet<>();
        Set<String> privileges = new HashSet<>();

        if (principalObj instanceof UserPrincipal) {
            UserPrincipal up = (UserPrincipal) principalObj;
            if (up.getId() != null) userId = up.getId().toString();
            username = up.getUsername();
            try { fullName = up.getFullName(); } catch (Throwable ignored) {}
            email = up.getEmail();

            roles = Optional.ofNullable(up.getRoles()).orElse(Collections.emptySet());
            privileges = Optional.ofNullable(up.getPrivileges()).orElse(Collections.emptySet());
        } else {
            username = principalObj.toString();
        }

        if ((fullName == null || fullName.isBlank() || email == null || email.isBlank() || roles.isEmpty()) && username != null) {
            Optional<User> maybe = userRepository.findByUsernameIgnoreCase(username);
            if (maybe.isPresent()) {
                User u = maybe.get();
                if (userId == null && u.getUserId() != null) userId = u.getUserId().toString();
                if (fullName == null || fullName.isBlank()) fullName = u.getFullName();
                if (email == null || email.isBlank()) email = u.getEmail();

                if (roles.isEmpty() && u.getRoles() != null) {
                    roles = u.getRoles().stream().map(Role::getRoleCode).collect(Collectors.toSet());
                }
                if (privileges.isEmpty() && u.getRoles() != null) {
                    privileges = u.getRoles().stream()
                            .flatMap(r -> r.getPrivileges().stream())
                            .map(Privilege::getPrivilegeCode)
                            .collect(Collectors.toSet());
                }
            }
        }

        Set<String> accessibleScreens = new HashSet<>();
        List<ScreenDto> accessibleScreensDetailed = new ArrayList<>();
        if (userId != null) {
            try {
                UUID uid = UUID.fromString(userId);
                List<String> codes = uiAccessService.getAccessibleScreens(uid);
                if (codes != null) accessibleScreens.addAll(codes);

                JsonNode routesNode = uiAccessService.getUserRoutes(uid);
                if (routesNode != null && routesNode.has("menu") && routesNode.get("menu").isArray()) {
                    for (JsonNode n : routesNode.get("menu")) {
                        String screenCode = n.has("screen_code") && !n.get("screen_code").isNull() ? n.get("screen_code").asText() : null;
                        String path = n.has("path") && !n.get("path").isNull() ? n.get("path").asText() : null;
                        String basePath = n.has("base_path") && !n.get("base_path").isNull() ? n.get("base_path").asText() : null;
                        String title = n.has("title") && !n.get("title").isNull() ? n.get("title").asText() : null;
                        String icon = n.has("icon") && !n.get("icon").isNull() ? n.get("icon").asText() : null;
                        Integer ordering = n.has("ordering") && n.get("ordering").isNumber() ? n.get("ordering").asInt() : null;
                        Boolean isMenu = n.has("is_menu") && !n.get("is_menu").isNull() ? n.get("is_menu").asBoolean() : null;
                        String parentCode = n.has("parent_code") && !n.get("parent_code").isNull() ? n.get("parent_code").asText() : null;

                        ScreenDto dto = new ScreenDto(screenCode, path, basePath, title, icon, ordering, isMenu, parentCode);
                        accessibleScreensDetailed.add(dto);
                    }
                }
            } catch (Exception ex) {

            }
        }

        MeResponse resp = new MeResponse(
                userId,
                username,
                fullName,
                email,
                roles,
                privileges,
                accessibleScreens,
                accessibleScreensDetailed
        );

        return ResponseEntity.ok(resp);
    }
}

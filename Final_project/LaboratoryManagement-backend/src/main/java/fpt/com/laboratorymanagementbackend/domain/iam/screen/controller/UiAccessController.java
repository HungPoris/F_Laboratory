package fpt.com.laboratorymanagementbackend.domain.iam.screen.controller;

import com.fasterxml.jackson.databind.JsonNode;
import fpt.com.laboratorymanagementbackend.domain.iam.screen.service.UiAccessService;
import fpt.com.laboratorymanagementbackend.security.userdetails.UserPrincipal;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/ui")
public class UiAccessController {

    private final UiAccessService uiAccessService;

    public UiAccessController(UiAccessService uiAccessService) {
        this.uiAccessService = uiAccessService;
    }

    @GetMapping("/accessible-screens")
    public ResponseEntity<?> getAccessibleScreens(@AuthenticationPrincipal UserPrincipal principal) {
        UUID userId = UUID.fromString(principal.getId().toString());
        List<String> screens = uiAccessService.getAccessibleScreens(userId);
        return ResponseEntity.ok(Map.of("accessible_screens", screens));
    }

    @GetMapping("/can-access")
    public ResponseEntity<?> canAccess(@AuthenticationPrincipal UserPrincipal principal,
                                       @RequestParam("basePath") String basePath) {
        UUID userId = UUID.fromString(principal.getId().toString());
        boolean allowed = uiAccessService.canAccessBasePath(userId, basePath);
        return ResponseEntity.ok(Map.of("allowed", allowed));
    }

    @GetMapping("/routes")
    public ResponseEntity<JsonNode> getRoutes(@AuthenticationPrincipal UserPrincipal principal) {
        UUID userId = UUID.fromString(principal.getId().toString());
        JsonNode routes = uiAccessService.getUserRoutes(userId);
        return ResponseEntity.ok(routes);
    }

    @GetMapping("/screen-actions")
    public ResponseEntity<?> getScreenActions(@AuthenticationPrincipal UserPrincipal principal,
                                              @RequestParam("screenCode") String screenCode) {
        UUID userId = UUID.fromString(principal.getId().toString());
        List<String> actions = uiAccessService.getActionsForScreen(userId, screenCode);
        return ResponseEntity.ok(Map.of("screen", screenCode, "actions", actions));
    }
}

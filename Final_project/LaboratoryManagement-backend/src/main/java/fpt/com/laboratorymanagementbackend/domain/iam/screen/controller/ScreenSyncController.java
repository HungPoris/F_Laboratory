package fpt.com.laboratorymanagementbackend.domain.iam.screen.controller;

import fpt.com.laboratorymanagementbackend.domain.iam.screen.dto.ScreenUpsertRequest;
import fpt.com.laboratorymanagementbackend.domain.iam.screen.entity.Screen;
import fpt.com.laboratorymanagementbackend.domain.iam.screen.repository.ScreenRepository;
import fpt.com.laboratorymanagementbackend.domain.iam.screen.service.ScreenSyncService;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/v1/screens")
public class ScreenSyncController {

    private final ScreenSyncService service;
    private final ScreenRepository screenRepository;

    public ScreenSyncController(ScreenSyncService service, ScreenRepository screenRepository) {
        this.service = service;
        this.screenRepository = screenRepository;
    }

    @GetMapping("/all")
    public ResponseEntity<List<Map<String,Object>>> getAllScreens() {
        List<Map<String,Object>> rows = screenRepository.findAll().stream().map(s -> {
            Map<String,Object> m = new HashMap<>();
            m.put("screen_code", s.getScreenCode());
            m.put("path", s.getPath());
            m.put("base_path", s.getBasePath());
            m.put("title", s.getTitle());
            m.put("icon", s.getIcon());
            m.put("ordering", s.getOrdering());
            m.put("parent_code", s.getParentCode());
            m.put("is_menu", s.getIsMenu());
            m.put("is_default", s.getIsDefault());
            m.put("is_public", s.getIsPublic());
            m.put("component_name", s.getComponentName());
            m.put("component_key", s.getComponentKey());
            return m;
        }).collect(Collectors.toList());
        return ResponseEntity.ok(rows);
    }

    @PostMapping("/sync")
    @PreAuthorize("hasRole('ADMIN')")
    public ResponseEntity<?> syncScreens(@RequestBody List<ScreenUpsertRequest> payload) {
        if (payload == null || payload.size() > 2000) {
            return ResponseEntity.badRequest().body(Map.of("error", "payload size invalid"));
        }
        ScreenSyncService.SyncResult res = service.upsertScreens(payload);
        return ResponseEntity.ok(Map.of("inserted", res.getInserted(), "updated", res.getUpdated()));
    }
}
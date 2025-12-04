package fpt.com.laboratorymanagementbackend.domain.iam.role.controller;

import fpt.com.laboratorymanagementbackend.domain.iam.role.dto.PrivilegeCreateRequest;
import fpt.com.laboratorymanagementbackend.domain.iam.role.dto.PrivilegeUpdateRequest;
import fpt.com.laboratorymanagementbackend.domain.iam.role.entity.Privilege;
import fpt.com.laboratorymanagementbackend.domain.iam.role.service.PrivilegeService;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.security.access.prepost.PreAuthorize;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/admin/privileges")
public class PrivilegeAdminController {
    private final PrivilegeService privilegeService;
    public PrivilegeAdminController(PrivilegeService privilegeService) {
        this.privilegeService = privilegeService;
    }

    @PreAuthorize("hasAuthority('privileges.view') or hasRole('ADMIN')")
    @GetMapping("/{id}")
    public ResponseEntity<Privilege> get(@PathVariable UUID id) {
        return ResponseEntity.ok(privilegeService.get(id));
    }

    @PreAuthorize("hasAuthority('privileges.view') or hasRole('ADMIN')")
    @GetMapping
    public ResponseEntity<Page<Privilege>> list(Pageable pageable,
                                                @RequestParam(value = "q", required = false) String q) {
        return ResponseEntity.ok(privilegeService.list(pageable, q));
    }

}

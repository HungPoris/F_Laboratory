package fpt.com.laboratorymanagementbackend.domain.iam.role.controller;

import fpt.com.laboratorymanagementbackend.domain.iam.role.dto.RoleCreateRequest;
import fpt.com.laboratorymanagementbackend.domain.iam.role.dto.RoleResponse;
import fpt.com.laboratorymanagementbackend.domain.iam.role.dto.RoleUpdateRequest;
import fpt.com.laboratorymanagementbackend.domain.iam.role.service.RoleService;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/admin/roles")
public class RoleAdminController {

    private final RoleService roleService;

    public RoleAdminController(RoleService roleService) {
        this.roleService = roleService;
    }

    @PreAuthorize("hasAuthority('role.view') or hasRole('ADMIN')")
    @GetMapping
    public ResponseEntity<Page<RoleResponse>> list(
            @RequestParam(value = "q", required = false) String q,
            @RequestParam(value = "status", required = false, defaultValue = "any") String status,
            @RequestParam(value = "page", required = false, defaultValue = "0") int page,
            @RequestParam(value = "size", required = false, defaultValue = "20") int size,
            @RequestParam(value = "sort", required = false, defaultValue = "roleName,asc") String sort
    ) {
        String[] sortParts = sort.split(",");
        Sort sortObj;
        if (sortParts.length >= 2) {
            sortObj = Sort.by(Sort.Direction.fromString(sortParts[1].trim()), sortParts[0].trim());
        } else {
            sortObj = Sort.by(sortParts[0].trim()).ascending();
        }
        Pageable pageable = PageRequest.of(Math.max(0, page), Math.max(1, size), sortObj);
        Page<RoleResponse> result = roleService.findAll(q, status, pageable);
        return ResponseEntity.ok(result);
    }


    @PreAuthorize("hasAuthority('role.create') or hasRole('ADMIN')")
    @PostMapping
    public ResponseEntity<RoleResponse> create(@RequestBody RoleCreateRequest request) {
        return ResponseEntity.ok(roleService.create(request));
    }

    @PreAuthorize("hasAuthority('role.view') or hasRole('ADMIN')")
    @GetMapping("/{id}")
    public ResponseEntity<RoleResponse> get(@PathVariable UUID id) {
        return ResponseEntity.ok(roleService.get(id));
    }

    @PreAuthorize("hasAuthority('role.update') or hasRole('ADMIN')")
    @PutMapping("/{id}")
    public ResponseEntity<RoleResponse> update(@PathVariable UUID id, @RequestBody RoleUpdateRequest request) {
        return ResponseEntity.ok(roleService.update(id, request));
    }

    @PreAuthorize("hasAuthority('role.delete') or hasRole('ADMIN')")
    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@PathVariable UUID id) {
        roleService.delete(id);
        return ResponseEntity.noContent().build();
    }

    @PreAuthorize("hasAuthority('role.assignprivilege') or hasRole('ADMIN')")
    @PostMapping("/{roleCode}/privileges")
    public ResponseEntity<RoleResponse> addPrivilege(
            @PathVariable String roleCode,
            @RequestParam String privilegeCode,
            @RequestParam(required = false) String privilegeName
    ) {
        return ResponseEntity.ok(
                roleService.addPrivilegeToRole(roleCode, privilegeCode, privilegeName == null ? privilegeCode : privilegeName)
        );
    }
}

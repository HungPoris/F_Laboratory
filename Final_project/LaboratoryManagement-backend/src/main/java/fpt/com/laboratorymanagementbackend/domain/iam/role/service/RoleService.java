package fpt.com.laboratorymanagementbackend.domain.iam.role.service;

import fpt.com.laboratorymanagementbackend.common.service.OutboxService;
import fpt.com.laboratorymanagementbackend.domain.iam.role.dto.RoleCreateRequest;
import fpt.com.laboratorymanagementbackend.domain.iam.role.dto.RoleResponse;
import fpt.com.laboratorymanagementbackend.domain.iam.role.dto.RoleUpdateRequest;
import fpt.com.laboratorymanagementbackend.domain.iam.role.entity.Privilege;
import fpt.com.laboratorymanagementbackend.domain.iam.role.entity.Role;
import fpt.com.laboratorymanagementbackend.domain.iam.role.repository.PrivilegeRepository;
import fpt.com.laboratorymanagementbackend.domain.iam.role.repository.RoleRepository;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.*;
import java.util.stream.Collectors;

@Service
public class RoleService {

    private final RoleRepository roleRepository;
    private final PrivilegeRepository privilegeRepository;
    private final OutboxService outboxService;

    public RoleService(RoleRepository roleRepository, PrivilegeRepository privilegeRepository, OutboxService outboxService) {
        this.roleRepository = roleRepository;
        this.privilegeRepository = privilegeRepository;
        this.outboxService = outboxService;
    }

    @Transactional(readOnly = true)
    public Role getEntity(UUID id) {
        return roleRepository.findById(id).orElseThrow(() -> new IllegalArgumentException("Role not found"));
    }

    @Transactional(readOnly = true)
    public RoleResponse get(UUID id) {
        return map(getEntity(id));
    }

    @Transactional(readOnly = true)
    public Page<RoleResponse> findAll(String q, String status, Pageable pageable) {
        String keyword = (q == null || q.isBlank()) ? null : q.trim();
        String statusFilter = (status == null || status.isBlank()) ? "any" : status.trim();
        Page<Role> page = roleRepository.searchByQAndStatus(keyword, statusFilter, pageable);
        return page.map(this::map);
    }


    @PreAuthorize("hasRole('ADMIN') or hasAuthority('role.create')")
    @Transactional
    public RoleResponse create(RoleCreateRequest req) {
        String code = req.getCode();
        String name = req.getName();
        if (code == null || code.isBlank() || name == null || name.isBlank()) {
            throw new IllegalArgumentException("Missing parameter code/name");
        }
        roleRepository.findByRoleCode(code).ifPresent(x -> { throw new IllegalArgumentException("Role already exists"); });
        Role r = new Role();
        r.setRoleCode(code);
        r.setRoleName(name);
        r.setRoleDescription(req.getDescription());
        r.setActive(req.getActive() != null ? req.getActive() : true);
        r.setSystemRole(Boolean.TRUE.equals(req.getSystem()));
        if (req.getPrivilegeIds() != null && !req.getPrivilegeIds().isEmpty()) {
            Set<Privilege> privs = new HashSet<>(privilegeRepository.findAllById(req.getPrivilegeIds()));
            r.setPrivileges(privs);
        }
        Role saved = roleRepository.save(r);
        Map<String, Object> payload = new HashMap<>();
        payload.put("event", "ROLE_CREATED");
        payload.put("role_code", code);
        outboxService.publish("lab.audit.events", payload);
        return map(saved);
    }

    @PreAuthorize("hasRole('ADMIN') or hasAuthority('role.update')")
    @Transactional
    public RoleResponse update(UUID id, RoleUpdateRequest req) {
        Role r = roleRepository.findById(id).orElseThrow(() -> new IllegalArgumentException("Role not found"));
        if (req.getName() != null && !req.getName().isBlank()) r.setRoleName(req.getName());
        if (req.getDescription() != null) r.setRoleDescription(req.getDescription());
        if (req.getActive() != null) r.setActive(req.getActive());
        if (req.getSystem() != null) r.setSystemRole(req.getSystem());
        if (req.getPrivilegeIds() != null) {
            Set<Privilege> privs = new HashSet<>(privilegeRepository.findAllById(req.getPrivilegeIds()));
            r.setPrivileges(privs);
        }
        Role saved = roleRepository.save(r);
        Map<String, Object> payload = new HashMap<>();
        payload.put("event", "ROLE_UPDATED");
        payload.put("role_id", id.toString());
        outboxService.publish("lab.audit.events", payload);
        return map(saved);
    }

    @PreAuthorize("hasRole('ADMIN') or hasAuthority('role.delete')")
    @Transactional
    public void delete(UUID id) {
        Role r = roleRepository.findById(id).orElseThrow(() -> new IllegalArgumentException("Role not found"));
        roleRepository.delete(r);
        Map<String, Object> payload = new HashMap<>();
        payload.put("event", "ROLE_DELETED");
        payload.put("role_id", id.toString());
        outboxService.publish("lab.audit.events", payload);
    }

    @PreAuthorize("hasRole('ADMIN') or hasAuthority('role.assignprivilege')")
    @Transactional
    public RoleResponse addPrivilegeToRole(String roleCode, String privilegeCode, String privilegeName) {
        Role r = roleRepository.findByRoleCode(roleCode).orElseThrow(() -> new IllegalArgumentException("Role not found"));
        Privilege p = privilegeRepository.findByPrivilegeCode(privilegeCode).orElseGet(() -> {
            Privilege np = new Privilege();
            np.setPrivilegeCode(privilegeCode);
            np.setPrivilegeName(privilegeName);
            return privilegeRepository.save(np);
        });
        boolean notExists = r.getPrivileges().stream().noneMatch(x -> p.getPrivilegeCode().equals(x.getPrivilegeCode()));
        if (notExists) {
            r.getPrivileges().add(p);
            roleRepository.save(r);
            Map<String, Object> payload = new HashMap<>();
            payload.put("event", "ROLE_PRIVILEGE_ADDED");
            payload.put("role_code", roleCode);
            payload.put("privilege_code", privilegeCode);
            outboxService.publish("lab.audit.events", payload);
        }
        return map(r);
    }

    private RoleResponse map(Role r) {
        return new RoleResponse(
                r.getRoleId(),
                r.getRoleCode(),
                r.getRoleName(),
                r.getRoleDescription(),
                r.isSystemRole(),
                r.isActive(),
                Optional.ofNullable(r.getPrivileges())
                        .map(privs -> privs.stream().filter(Objects::nonNull).map(Privilege::getPrivilegeCode).collect(Collectors.toList()))
                        .orElse(List.of())
        );
    }
}

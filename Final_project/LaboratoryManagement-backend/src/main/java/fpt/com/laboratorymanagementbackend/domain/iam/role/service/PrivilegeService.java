package fpt.com.laboratorymanagementbackend.domain.iam.role.service;

import fpt.com.laboratorymanagementbackend.domain.iam.role.entity.Privilege;
import fpt.com.laboratorymanagementbackend.domain.iam.role.repository.PrivilegeRepository;
import fpt.com.laboratorymanagementbackend.common.service.OutboxService;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.UUID;
import java.util.HashMap;
import java.util.Map;

@Service
public class PrivilegeService {
    private final PrivilegeRepository privilegeRepository;
    private final OutboxService outboxService;
    public PrivilegeService(PrivilegeRepository privilegeRepository, OutboxService outboxService) {
        this.privilegeRepository = privilegeRepository;
        this.outboxService = outboxService;
    }


    public Privilege get(UUID id) {
        return privilegeRepository.findById(id).orElseThrow(() -> new IllegalArgumentException("Not found"));
    }

    public Page<Privilege> list(Pageable pageable, String q) {
        if (q == null || q.trim().isEmpty()) {
            return privilegeRepository.findAll(pageable);
        }
        String keyword = q.trim().toLowerCase();
        return privilegeRepository.searchByKeyword(keyword, pageable);
    }



}

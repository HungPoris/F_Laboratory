package fpt.com.laboratorymanagementbackend.common.address.service;

import fpt.com.laboratorymanagementbackend.common.address.dto.ProvinceOption;
import fpt.com.laboratorymanagementbackend.common.address.entity.Commune;
import fpt.com.laboratorymanagementbackend.common.address.repository.CommuneRepository;
import fpt.com.laboratorymanagementbackend.common.address.repository.ProvinceRepository;
import org.springframework.data.domain.*;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.stream.Collectors;

@Service
public class AddressService {
    private final ProvinceRepository provinceRepository;
    private final CommuneRepository communeRepository;

    public AddressService(ProvinceRepository provinceRepository, CommuneRepository communeRepository) {
        this.provinceRepository = provinceRepository;
        this.communeRepository = communeRepository;
    }

    public List<ProvinceOption> provinces() {
        return provinceRepository.findAll().stream()
                .sorted((a,b) -> a.getCode().compareTo(b.getCode()))
                .map(p -> new ProvinceOption(p.getCode(), p.getName()))
                .collect(Collectors.toList());
    }

    public Page<Commune> communes(String provinceCode, String q, int page, int size, String sort) {
        Pageable pageable = PageRequest.of(Math.max(page,0), Math.max(size,1), parseSort(sort));
        String p = isBlank(provinceCode) ? null : provinceCode.trim();
        String s = isBlank(q) ? null : q.trim();
        return communeRepository.searchByProvinceAndQuery(p, s, pageable);
    }

    private boolean isBlank(String s) { return s == null || s.isBlank(); }

    private Sort parseSort(String sort) {
        if (sort == null || sort.isBlank()) return Sort.by(Sort.Order.asc("name"));
        String[] parts = sort.split(",");
        Sort.Order o = parts.length > 1 && "desc".equalsIgnoreCase(parts[1])
                ? Sort.Order.desc(parts[0])
                : Sort.Order.asc(parts[0]);
        return Sort.by(o);
    }
}
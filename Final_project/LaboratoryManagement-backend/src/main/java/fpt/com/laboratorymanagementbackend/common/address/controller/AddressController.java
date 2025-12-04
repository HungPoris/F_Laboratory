package fpt.com.laboratorymanagementbackend.common.address.controller;

import fpt.com.laboratorymanagementbackend.common.address.dto.ProvinceOption;
import fpt.com.laboratorymanagementbackend.common.address.entity.Commune;
import fpt.com.laboratorymanagementbackend.common.address.service.AddressService;
import org.springframework.data.domain.Page;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/addresses")
public class AddressController {
    private final AddressService svc;
    public AddressController(AddressService svc) { this.svc = svc; }

    @GetMapping("/provinces")
    public Map<String, Object> provinces() {
        List<ProvinceOption> data = svc.provinces();
        Map<String, Object> res = new HashMap<>();
        res.put("provinces", data);
        res.put("total", data.size());
        return res;
    }

    @GetMapping("/communes")
    public Map<String, Object> communes(@RequestParam(required = false) String provinceCode,
                                        @RequestParam(required = false) String q,
                                        @RequestParam(defaultValue = "0") int page,
                                        @RequestParam(defaultValue = "200") int size,
                                        @RequestParam(required = false) String sort) {
        Page<Commune> p = svc.communes(provinceCode, q, page, size, sort);
        Map<String, Object> res = new HashMap<>();
        res.put("communes", p.getContent());
        res.put("page", p.getNumber());
        res.put("size", p.getSize());
        res.put("total", p.getTotalElements());
        res.put("totalPages", p.getTotalPages());
        return res;
    }
}

package fpt.com.testorderservices.domain.medicalrecord.controller;

import fpt.com.testorderservices.common.util.PaginationResponse;
import fpt.com.testorderservices.domain.medicalrecord.dto.MedicalRecordSystemDto;
import fpt.com.testorderservices.domain.medicalrecord.service.MedicalRecordService;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping(value = "/api/v1/patient/all-medical-records", produces = "application/json")
@RequiredArgsConstructor
// 👇 SỬA TẠI ĐÂY: Cho phép tất cả các nguồn (để test) hoặc thêm port 5173
@CrossOrigin(originPatterns = "*")
public class SystemMedicalRecordController {

    private final MedicalRecordService service;

    @GetMapping
    @PreAuthorize("hasAuthority('view.all_medicalrecord') or hasRole('ADMIN')")
    public ResponseEntity<PaginationResponse<MedicalRecordSystemDto>> getAllSystemRecords(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "10") int size,
            @RequestParam(required = false) String search
    ) {
        Pageable pageable = PageRequest.of(page, size, Sort.by("visitDate").descending());
        return ResponseEntity.ok(service.getSystemRecordsWithFilter(search, pageable));
    }
}
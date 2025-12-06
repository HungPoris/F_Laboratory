package fpt.com.testorderservices.domain.medicalrecord.controller;

import fpt.com.testorderservices.domain.medicalrecord.entity.MedicalRecord;
import fpt.com.testorderservices.domain.medicalrecord.service.MedicalRecordService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import java.util.*;

@RestController
@RequestMapping(value = "/api/v1/patients/{patientId}/medical-records", produces = "application/json")
@RequiredArgsConstructor
@CrossOrigin(origins = "http://localhost:3000")
public class MedicalRecordController {

    private final MedicalRecordService service;

    @GetMapping("/all")
    @PreAuthorize("hasAuthority('medical_records.view') or hasRole('ADMIN')")
    public ResponseEntity<List<MedicalRecord>> getAll() {
        return ResponseEntity.ok(service.getAll());
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasAuthority('medical_records.view') or hasRole('ADMIN')")
    public ResponseEntity<MedicalRecord> getById(@PathVariable UUID id) {
        return service.getById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @GetMapping
    @PreAuthorize("hasAuthority('medical_records.view') or hasRole('ADMIN')")
    public ResponseEntity<List<MedicalRecord>> getByPatient(@PathVariable UUID patientId) {
        return ResponseEntity.ok(service.getByPatientId(patientId));
    }

    @PostMapping
    @PreAuthorize("hasAuthority('medical_records.create') or hasRole('ADMIN')")
    public ResponseEntity<MedicalRecord> create(@RequestBody MedicalRecord record) {
        // createdBy sẽ được tự động điền nhờ JPA Auditing (xem phần sửa Entity bên dưới)
        return ResponseEntity.ok(service.create(record));
    }

    @PutMapping("/{id}")
    @PreAuthorize("hasAuthority('medical_records.edit') or hasRole('ADMIN')")
    public ResponseEntity<MedicalRecord> update(@PathVariable UUID id, @RequestBody MedicalRecord record) {
        // updatedBy sẽ được tự động điền nhờ JPA Auditing
        return ResponseEntity.ok(service.update(id, record));
    }

    // 🗑️ [SỬA] Thêm userId để lưu vết người xóa
    @DeleteMapping("/{id}")
    @PreAuthorize("hasAnyAuthority('medical_records.delete', 'SCREEN:MEDICAL_RECORD_DETAIL:DELETE') or hasRole('ADMIN')")
    public ResponseEntity<Void> delete(@PathVariable UUID id,
                                       @AuthenticationPrincipal String userId) { // Nhận String userId
        if (userId == null) {
            return ResponseEntity.badRequest().build();
        }
        service.softDelete(id, UUID.fromString(userId)); // Truyền xuống service
        return ResponseEntity.noContent().build();
    }

    // 🛠️ [SỬA] Sửa kiểu dữ liệu Principal từ Jwt sang String
    @GetMapping("/me")
    @PreAuthorize("isAuthenticated() and hasAuthority('system.read_only')")
    public ResponseEntity<?> getMyRecord(@AuthenticationPrincipal String userId) {
        // Vì principal là String userId, ta trả về trực tiếp
        return ResponseEntity.ok(
                Map.of("userId", userId != null ? userId : "N/A", "message", "User info retrieved from Principal String")
        );
    }
}
package fpt.com.testorderservices.domain.patient.controller;

import fpt.com.testorderservices.common.util.PaginationResponse;
import fpt.com.testorderservices.domain.patient.dto.PatientDTO;
import fpt.com.testorderservices.domain.patient.entity.Patient;
import fpt.com.testorderservices.domain.patient.service.PatientService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/patients")
public class PatientController {

    @Autowired
    private PatientService patientService;

    @GetMapping("/search")
    @PreAuthorize("hasAuthority('patient.view') or hasRole('ADMIN')")
    public ResponseEntity<List<PatientDTO>> searchPatients(@RequestParam("name") String name) {
        List<PatientDTO> results = patientService.searchPatientsDTO(name);
        return results.isEmpty() ? ResponseEntity.noContent().build() : ResponseEntity.ok(results);
    }

    @GetMapping
    @PreAuthorize("hasAuthority('patient.view') or hasRole('ADMIN')")
    public ResponseEntity<PaginationResponse<PatientDTO>> getAllPatients(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "10") int size,
            @RequestParam Map<String, String> params
    ) {
        Pageable pageable = PageRequest.of(page, size, Sort.by("createdAt").descending());
        return ResponseEntity.ok(patientService.getPatientsWithFilter(params, pageable));
    }

    @GetMapping("/{id}")
    @PreAuthorize("hasAnyAuthority('patient.view_detail', 'SCREEN:PATIENT_DETAIL', 'ADMIN')")
    public ResponseEntity<PatientDTO> getPatientById(@PathVariable("id") UUID id) {
        return patientService.getPatientDtoById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @PostMapping
    @PreAuthorize("hasAnyAuthority('patient.create', 'SCREEN:PATIENT_CREATE:VIEW', 'ADMIN')")
    // Đổi ResponseEntity<Patient> thành ResponseEntity<PatientDTO>
    public ResponseEntity<PatientDTO> createPatient(@RequestBody Patient patient) {
        return ResponseEntity.ok(patientService.createPatient(patient));
    }

    @PutMapping("/{id}")
    @PreAuthorize("hasAnyAuthority('patient.modify', 'SCREEN:PATIENT_EDIT:VIEW', 'ADMIN')")
    // Đổi ResponseEntity<Patient> thành ResponseEntity<PatientDTO>
    public ResponseEntity<PatientDTO> updatePatient(@PathVariable("id") UUID id, @RequestBody Patient patient) {
        return ResponseEntity.ok(patientService.updatePatient(id, patient));
    }

    // 🗑️ Xóa - [SỬA LỖI] Nhận String userId thay vì Jwt object
    @DeleteMapping("/{id}")
    @PreAuthorize("hasAuthority('patient.delete') or hasRole('ADMIN')")
    public ResponseEntity<String> deletePatient(@PathVariable("id") UUID id,
                                                @AuthenticationPrincipal String userId) { // Sửa từ Jwt thành String
        if (userId == null) {
            return ResponseEntity.badRequest().body("Invalid user token");
        }
        // Vì userId là String (do IamAuthenticationFilter set), ta parse trực tiếp
        patientService.deletePatient(id, UUID.fromString(userId));
        return ResponseEntity.ok("Deleted successfully");
    }
    // 👇 THÊM MỚI: API thống kê
    @GetMapping("/stats")
    @PreAuthorize("hasAuthority('patient.view') or hasRole('ADMIN')")
    public ResponseEntity<Map<String, Long>> getPatientStats() {
        return ResponseEntity.ok(patientService.getPatientStatistics());
    }
}
package fpt.com.testorderservices.domain.patient.service;

import fpt.com.testorderservices.common.exception.BusinessException;
import fpt.com.testorderservices.common.util.PaginationResponse;
import fpt.com.testorderservices.domain.patient.dto.PatientDTO;
import fpt.com.testorderservices.domain.patient.entity.Patient;
import fpt.com.testorderservices.domain.patient.repository.PatientRepository;
import fpt.com.testorderservices.security.dto.InternalUserSummaryResponse;
import fpt.com.testorderservices.security.service.IamExternalService;
import jakarta.persistence.criteria.Predicate;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.*;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import java.util.stream.Stream;

@Service
@RequiredArgsConstructor
public class PatientService {

    private final PatientRepository patientRepository;
    private final IamExternalService iamExternalService;

    private static final String EMAIL_REGEX = "^[A-Za-z0-9+_.-]+@[A-Za-z0-9.-]+$";

    // ... (Giữ nguyên Helper Methods: fetchUserMap, mapToDTO, buildUserSummary) ...
    // Lưu ý: mapToDTO và fetchUserMap giữ nguyên code từ bước trước

    private Map<UUID, InternalUserSummaryResponse> fetchUserMap(List<Patient> patients) {
        if (patients == null || patients.isEmpty()) return Collections.emptyMap();
        List<UUID> userIds = patients.stream()
                .flatMap(p -> Stream.of(p.getCreatedBy(), p.getUpdatedBy()))
                .filter(Objects::nonNull)
                .collect(Collectors.toList());
        return iamExternalService.getUsersInfo(userIds);
    }

    private PatientDTO mapToDTO(Patient patient, Map<UUID, InternalUserSummaryResponse> userMap) {
        return PatientDTO.builder()
                .patientId(patient.getPatientId())
                .fullName(patient.getFullName())
                .dob(patient.getDob())
                .gender(patient.getGender())
                .contactNumber(patient.getContactNumber())
                .email(patient.getEmail())
                .address(patient.getAddress())
                .lastTestDate(patient.getLastTestDate())
                .isDeleted(patient.getIsDeleted())
                .createdAt(patient.getCreatedAt())
                .updatedAt(patient.getUpdatedAt())
                .createdBy(buildUserSummary(patient.getCreatedBy(), userMap))
                .updatedBy(buildUserSummary(patient.getUpdatedBy(), userMap))
                .build();
    }

    private PatientDTO.UserSummary buildUserSummary(UUID userId, Map<UUID, InternalUserSummaryResponse> userMap) {
        if (userId == null) return null;
        InternalUserSummaryResponse userInfo = userMap.get(userId);
        String displayName = "Unknown";
        if (userInfo != null) {
            displayName = (userInfo.getFullName() != null && !userInfo.getFullName().isBlank())
                    ? userInfo.getFullName()
                    : userInfo.getUsername();
        }
        return PatientDTO.UserSummary.builder().userID(userId).userName(displayName).build();
    }

    private void validatePatientData(Patient patient) {
        if (patient.getFullName() == null || patient.getFullName().trim().isEmpty()) throw new BusinessException("Tên không được để trống.");
        if (patient.getDob() == null || patient.getDob().isAfter(LocalDate.now())) throw new BusinessException("Ngày sinh không hợp lệ.");
        if (patient.getEmail() != null && !Pattern.matches(EMAIL_REGEX, patient.getEmail())) throw new BusinessException("Email không hợp lệ.");
    }

    // --- Main Methods (Updated) ---

    // 1️⃣ Sửa kiểu trả về từ Patient thành PatientDTO
    public PatientDTO createPatient(Patient patient) {
        validatePatientData(patient);
        if (patientRepository.existsByEmailAndIsDeletedFalse(patient.getEmail())) {
            throw new BusinessException("Email đã tồn tại.");
        }

        Patient savedPatient = patientRepository.save(patient);

        // 2️⃣ Map sang DTO để lấy thông tin User
        Map<UUID, InternalUserSummaryResponse> userMap = fetchUserMap(Collections.singletonList(savedPatient));
        return mapToDTO(savedPatient, userMap);
    }

    // 1️⃣ Sửa kiểu trả về từ Patient thành PatientDTO
    public PatientDTO updatePatient(UUID patientId, Patient updatedPatient) {
        validatePatientData(updatedPatient);

        Patient savedPatient = patientRepository.findByPatientIdAndIsDeletedFalse(patientId)
                .map(existing -> {
                    if (patientRepository.existsByEmailAndPatientIdNotAndIsDeletedFalse(updatedPatient.getEmail(), patientId)) {
                        throw new BusinessException("Email đã tồn tại.");
                    }
                    existing.setFullName(updatedPatient.getFullName());
                    existing.setDob(updatedPatient.getDob());
                    existing.setGender(updatedPatient.getGender());
                    existing.setContactNumber(updatedPatient.getContactNumber());
                    existing.setEmail(updatedPatient.getEmail());
                    existing.setAddress(updatedPatient.getAddress());

                    return patientRepository.save(existing);
                })
                .orElseThrow(() -> new BusinessException("Patient not found"));

        // 2️⃣ Map sang DTO để hiển thị tên User Update
        Map<UUID, InternalUserSummaryResponse> userMap = fetchUserMap(Collections.singletonList(savedPatient));
        return mapToDTO(savedPatient, userMap);
    }

    // 🔹 Các hàm GET, SEARCH, FILTER giữ nguyên logic mapping DTO
    public List<PatientDTO> getAllPatientsDTO() {
        List<Patient> patients = patientRepository.findAll().stream()
                .filter(p -> !Boolean.TRUE.equals(p.getIsDeleted()))
                .collect(Collectors.toList());
        Map<UUID, InternalUserSummaryResponse> userMap = fetchUserMap(patients);
        return patients.stream().map(p -> mapToDTO(p, userMap)).collect(Collectors.toList());
    }

    public Optional<PatientDTO> getPatientDtoById(UUID patientId) {
        return patientRepository.findByPatientIdAndIsDeletedFalse(patientId)
                .map(p -> {
                    Map<UUID, InternalUserSummaryResponse> userMap = fetchUserMap(Collections.singletonList(p));
                    return mapToDTO(p, userMap);
                });
    }

    public List<PatientDTO> searchPatientsDTO(String name) {
        List<Patient> patients = patientRepository.findByFullNameContainingIgnoreCaseAndIsDeletedFalse(name);
        Map<UUID, InternalUserSummaryResponse> userMap = fetchUserMap(patients);
        return patients.stream().map(p -> mapToDTO(p, userMap)).collect(Collectors.toList());
    }

    public void deletePatient(UUID patientId, UUID deletedBy) {
        patientRepository.findByPatientIdAndIsDeletedFalse(patientId).ifPresent(p -> {
            p.setIsDeleted(true);
            p.setDeletedBy(deletedBy); // Cái này vẫn set thủ công vì là delete mềm
            p.setDeletedAt(LocalDateTime.now());
            patientRepository.save(p);
        });
    }

    public PaginationResponse<PatientDTO> getPatientsWithFilter(Map<String, String> filters, Pageable pageable) {
        // ... (Giữ nguyên logic filter như cũ) ...
        Specification<Patient> spec = (root, query, cb) -> {
            List<Predicate> predicates = new ArrayList<>();
            predicates.add(cb.notEqual(root.get("isDeleted"), true));

            if (filters.containsKey("name") && StringUtils.hasText(filters.get("name")))
                predicates.add(cb.like(cb.lower(root.get("fullName")), "%" + filters.get("name").toLowerCase() + "%"));
            if (filters.containsKey("phone") && StringUtils.hasText(filters.get("phone")))
                predicates.add(cb.like(root.get("contactNumber"), "%" + filters.get("phone") + "%"));
            if (filters.containsKey("email") && StringUtils.hasText(filters.get("email")))
                predicates.add(cb.like(cb.lower(root.get("email")), "%" + filters.get("email").toLowerCase() + "%"));
            if (filters.containsKey("gender") && StringUtils.hasText(filters.get("gender"))) {
                String gender = filters.get("gender");
                if (!gender.equalsIgnoreCase("all")) predicates.add(cb.equal(cb.lower(root.get("gender")), gender.toLowerCase()));
            }
            if (filters.containsKey("dob") && StringUtils.hasText(filters.get("dob"))) {
                try {
                    LocalDate date = LocalDate.parse(filters.get("dob"));
                    String operator = filters.getOrDefault("dobOperator", "is");
                    switch (operator) {
                        case "before": predicates.add(cb.lessThan(root.get("dob"), date)); break;
                        case "after": predicates.add(cb.greaterThan(root.get("dob"), date)); break;
                        case "between":
                            if (filters.containsKey("dobTo") && StringUtils.hasText(filters.get("dobTo"))) {
                                LocalDate dateTo = LocalDate.parse(filters.get("dobTo"));
                                predicates.add(cb.between(root.get("dob"), date, dateTo));
                            }
                            break;
                        default: predicates.add(cb.equal(root.get("dob"), date)); break;
                    }
                } catch (Exception e) {}
            }
            return cb.and(predicates.toArray(new Predicate[0]));
        };

        Page<Patient> pageResult = patientRepository.findAll(spec, pageable);
        Map<UUID, InternalUserSummaryResponse> userMap = fetchUserMap(pageResult.getContent());
        List<PatientDTO> dtos = pageResult.getContent().stream().map(p -> mapToDTO(p, userMap)).collect(Collectors.toList());

        return PaginationResponse.<PatientDTO>builder()
                .items(dtos)
                .currentPage(pageResult.getNumber())
                .totalPages(pageResult.getTotalPages())
                .totalElements(pageResult.getTotalElements())
                .pageSize(pageResult.getSize())
                .build();
    }
    public Map<String, Long> getPatientStatistics() {
        long total = patientRepository.countByIsDeletedFalse();

        // 👇 [SỬA] Gọi hàm IgnoreCase
        long male = patientRepository.countByGenderIgnoreCaseAndIsDeletedFalse("Male");
        long female = patientRepository.countByGenderIgnoreCaseAndIsDeletedFalse("Female");

        // Nếu có giới tính khác hoặc null, số còn lại = Total - (Male + Female)
        long others = total - (male + female);
        // Đảm bảo không âm (phòng trường hợp data lỗi)
        if (others < 0) others = 0;

        Map<String, Long> stats = new HashMap<>();
        stats.put("total", total);
        stats.put("male", male);
        stats.put("female", female);
        stats.put("others", others);

        return stats;
    }
}
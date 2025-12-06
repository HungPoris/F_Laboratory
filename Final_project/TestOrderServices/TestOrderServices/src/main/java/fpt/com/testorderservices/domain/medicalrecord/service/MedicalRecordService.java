package fpt.com.testorderservices.domain.medicalrecord.service;

import fpt.com.testorderservices.common.exception.BusinessException;
import fpt.com.testorderservices.common.util.PaginationResponse;
import fpt.com.testorderservices.domain.medicalrecord.dto.MedicalRecordSystemDto;
import fpt.com.testorderservices.domain.medicalrecord.entity.MedicalRecord;
import fpt.com.testorderservices.domain.medicalrecord.repository.MedicalRecordRepository;
import fpt.com.testorderservices.domain.patient.entity.Patient;
import jakarta.persistence.criteria.Join;
import jakarta.persistence.criteria.JoinType;
import jakarta.persistence.criteria.Predicate;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class MedicalRecordService {

    private final MedicalRecordRepository repository;

    // --- VALIDATION ---
    private void validateMedicalRecord(MedicalRecord record) {
        if (record.getPatientId() == null) {
            throw new BusinessException("Mã bệnh nhân (Patient ID) là bắt buộc.");
        }
        if (!StringUtils.hasText(record.getDiagnosis())) {
            throw new BusinessException("Chẩn đoán (Diagnosis) là bắt buộc.");
        }
    }

    // --- BASIC READ ---
    @Transactional(readOnly = true)
    public List<MedicalRecord> getAll() {
        return repository.findAll();
    }

    @Transactional(readOnly = true)
    public Optional<MedicalRecord> getById(UUID id) {
        return repository.findById(id);
    }

    @Transactional(readOnly = true)
    public List<MedicalRecord> getByPatientId(UUID patientId) {
        return repository.findByPatientIdAndIsDeletedFalse(patientId);
    }

    // --- CREATE (UPDATED LOGIC) ---
    @Transactional
    public MedicalRecord create(MedicalRecord record) {
        validateMedicalRecord(record);

        // LOGIC XỬ LÝ MÃ HỒ SƠ (RECORD CODE)
        if (StringUtils.hasText(record.getRecordCode())) {
            // Case 1: Người dùng tự nhập mã (hoặc import dữ liệu)
            if (repository.existsByRecordCode(record.getRecordCode())) {
                throw new BusinessException("Mã hồ sơ bệnh án '" + record.getRecordCode() + "' đã tồn tại.");
            }
            // Nếu chưa tồn tại -> Giữ nguyên mã người dùng nhập
        } else {
            // Case 2: Người dùng không nhập -> Hệ thống tự sinh mã an toàn
            record.setRecordCode(generateSafeMedicalRecordCode());
        }

        // Set thông tin audit
        record.setCreatedAt(LocalDateTime.now());
        record.setUpdatedAt(LocalDateTime.now());
        record.setIsDeleted(false);

        return repository.save(record);
    }

    // --- UPDATE ---
    @Transactional
    public MedicalRecord update(UUID id, MedicalRecord updatedRecord) {
        MedicalRecord existingRecord = repository.findById(id)
                .orElseThrow(() -> new BusinessException("Không tìm thấy bệnh án với ID: " + id));

        // Chỉ update các trường cho phép
        existingRecord.setDiagnosis(updatedRecord.getDiagnosis());
        existingRecord.setChiefComplaint(updatedRecord.getChiefComplaint());
        existingRecord.setClinicalNotes(updatedRecord.getClinicalNotes());
        existingRecord.setDepartments(updatedRecord.getDepartments());
        existingRecord.setTestOrderIds(updatedRecord.getTestOrderIds());
        existingRecord.setLastTestDate(updatedRecord.getLastTestDate());

        // Update audit
        existingRecord.setUpdatedAt(LocalDateTime.now());

        validateMedicalRecord(existingRecord);
        return repository.save(existingRecord);
    }

    // --- SOFT DELETE ---
    @Transactional
    public void softDelete(UUID id, UUID deletedBy) { // Thêm tham số deletedBy
        repository.findById(id).ifPresent(record -> {
            record.setIsDeleted(true);
            record.setDeletedAt(LocalDateTime.now());
            record.setDeletedBy(deletedBy); // Lưu người xóa
            repository.save(record);
        });
    }

    // --- FILTER & SEARCH (SYSTEM VIEW) ---
    @Transactional(readOnly = true)
    public PaginationResponse<MedicalRecordSystemDto> getSystemRecordsWithFilter(String search, Pageable pageable) {
        Specification<MedicalRecord> spec = (root, query, cb) -> {
            List<Predicate> predicates = new ArrayList<>();

            // 1. Luôn lọc bản ghi chưa xóa
            predicates.add(cb.notEqual(root.get("isDeleted"), true));

            // 2. Search keyword
            if (StringUtils.hasText(search)) {
                String searchLower = "%" + search.toLowerCase() + "%";
                Join<MedicalRecord, Patient> patientJoin = root.join("patient", JoinType.LEFT);

                Predicate codePred = cb.like(cb.lower(root.get("recordCode")), searchLower);
                Predicate diagPred = cb.like(cb.lower(root.get("diagnosis")), searchLower);
                Predicate namePred = cb.like(cb.lower(patientJoin.get("fullName")), searchLower);

                predicates.add(cb.or(codePred, diagPred, namePred));
            }

            return cb.and(predicates.toArray(new Predicate[0]));
        };

        Page<MedicalRecord> pageResult = repository.findAll(spec, pageable);

        List<MedicalRecordSystemDto> dtos = pageResult.getContent().stream()
                .map(this::mapToSystemDto)
                .collect(Collectors.toList());

        return PaginationResponse.<MedicalRecordSystemDto>builder()
                .items(dtos)
                .currentPage(pageResult.getNumber())
                .totalPages(pageResult.getTotalPages())
                .totalElements(pageResult.getTotalElements())
                .pageSize(pageResult.getSize())
                .build();
    }

    // --- HELPER METHODS ---

    /**
     * Sinh mã Record Code an toàn, tránh trùng lặp
     * Format: 920 + 015 + YY + xxxxxx (VD: 92001525000001)
     */
    private String generateSafeMedicalRecordCode() {
        String provinceCode = "920";
        String hospitalCode = "015";
        String yearCode = String.valueOf(LocalDate.now().getYear()).substring(2);
        String prefix = provinceCode + hospitalCode + yearCode; // VD: 92001525

        // Lấy mã lớn nhất hiện tại trong DB có prefix này
        // PageRequest.of(0, 1) tương đương LIMIT 1
        List<String> lastCodes = repository.findLastRecordCode(prefix, PageRequest.of(0, 1));

        long nextSequence = 1;

        if (!lastCodes.isEmpty()) {
            String lastCode = lastCodes.get(0);
            try {
                // Cắt phần đuôi số để +1
                String currentSeqStr = lastCode.substring(prefix.length());
                nextSequence = Long.parseLong(currentSeqStr) + 1;
            } catch (Exception e) {
                // Fallback nếu format cũ bị sai: dùng count + 1
                nextSequence = repository.count() + 1;
            }
        }

        String newCode = prefix + String.format("%06d", nextSequence);

        // SAFETY LOOP: Kiểm tra lần cuối xem mã sinh ra có trùng không
        // Nếu trùng (do concurrency cao), tiếp tục tăng sequence
        while (repository.existsByRecordCode(newCode)) {
            nextSequence++;
            newCode = prefix + String.format("%06d", nextSequence);
        }

        return newCode;
    }

    private MedicalRecordSystemDto mapToSystemDto(MedicalRecord record) {
        return MedicalRecordSystemDto.builder()
                .medicalRecordId(record.getMedicalRecordId())
                .patientId(record.getPatientId())
                .recordCode(record.getRecordCode())
                .patientName(record.getPatient() != null ? record.getPatient().getFullName() : "Unknown Patient")
                .diagnosis(record.getDiagnosis())
                .visitDate(record.getVisitDate())
                .lastTestDate(record.getLastTestDate())
                .build();
    }

    // Pagination cho Patient View
    public PaginationResponse<MedicalRecord> getByPatientIdWithPagination(UUID patientId, Pageable pageable) {
        Page<MedicalRecord> page = repository.findByPatientIdAndIsDeletedFalse(patientId, pageable);
        return PaginationResponse.fromPage(page);
    }
}
package fpt.com.testorderservices.domain.patient.repository;

import fpt.com.testorderservices.domain.patient.entity.Patient;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface PatientRepository extends JpaRepository<Patient, UUID>, JpaSpecificationExecutor<Patient> {
    Optional<Patient> findByPatientIdAndIsDeletedFalse(UUID patientId);
    List<Patient> findByFullNameContainingIgnoreCaseAndIsDeletedFalse(String fullName);

    boolean existsByEmailAndIsDeletedFalse(String email);
    boolean existsByEmailAndPatientIdNotAndIsDeletedFalse(String email, UUID patientId);

    // 👇 [SỬA] Thêm IgnoreCase để đếm không phân biệt hoa thường (MALE == Male)
    long countByGenderIgnoreCaseAndIsDeletedFalse(String gender);

    long countByIsDeletedFalse();
}
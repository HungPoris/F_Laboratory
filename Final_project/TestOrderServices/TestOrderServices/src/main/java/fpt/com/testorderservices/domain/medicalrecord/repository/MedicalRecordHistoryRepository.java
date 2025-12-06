package fpt.com.testorderservices.domain.medicalrecord.repository;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;
import fpt.com.testorderservices.domain.medicalrecord.entity.MedicalRecordHistory;

import java.util.UUID;

@Repository
public interface MedicalRecordHistoryRepository extends JpaRepository<MedicalRecordHistory, UUID> {
}

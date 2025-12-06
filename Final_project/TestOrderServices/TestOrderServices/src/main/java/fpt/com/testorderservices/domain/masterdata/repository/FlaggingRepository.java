package fpt.com.testorderservices.domain.masterdata.repository;

import fpt.com.testorderservices.domain.masterdata.entity.Flagging;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface FlaggingRepository extends JpaRepository<Flagging, UUID> {

    List<Flagging> findByTestType_IdAndIsActive(UUID testTypeId, Boolean isActive);

    List<Flagging> findByTestType_IdOrderByFlagLevelDesc(UUID testTypeId);
}

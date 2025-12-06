package fpt.com.testorderservices.domain.masterdata.repository;

import fpt.com.testorderservices.domain.masterdata.entity.TestTypeInstrument;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

public interface TestTypeInstrumentRepository
        extends JpaRepository<TestTypeInstrument, UUID> {

    Optional<TestTypeInstrument> findFirstByTestType_Id(UUID testTypeId);

}

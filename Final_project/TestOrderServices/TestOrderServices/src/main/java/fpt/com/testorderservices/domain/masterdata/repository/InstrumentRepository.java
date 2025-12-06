package fpt.com.testorderservices.domain.masterdata.repository;

import fpt.com.testorderservices.domain.masterdata.entity.Instrument;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

public interface InstrumentRepository extends JpaRepository<Instrument, UUID> {

    Optional<Instrument> findByCode(String code);
}

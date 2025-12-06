package fpt.com.testorderservices.domain.masterdata.repository;

import fpt.com.testorderservices.domain.masterdata.entity.Reagent;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

public interface ReagentRepository extends JpaRepository<Reagent, UUID> {
}

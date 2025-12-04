package fpt.com.laboratorymanagementbackend.domain.iam.screen.repository;

import fpt.com.laboratorymanagementbackend.domain.iam.screen.entity.Screen;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

public interface ScreenRepository extends JpaRepository<Screen, UUID> {
    Optional<Screen> findByScreenCode(String screenCode);
    Optional<Screen> findByScreenCodeIgnoreCase(String screenCode);
}

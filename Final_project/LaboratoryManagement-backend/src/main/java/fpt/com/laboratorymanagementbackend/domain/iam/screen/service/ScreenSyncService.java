package fpt.com.laboratorymanagementbackend.domain.iam.screen.service;

import fpt.com.laboratorymanagementbackend.domain.iam.screen.dto.ScreenUpsertRequest;
import fpt.com.laboratorymanagementbackend.domain.iam.screen.entity.Screen;
import fpt.com.laboratorymanagementbackend.domain.iam.screen.repository.ScreenRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;

@Service
public class ScreenSyncService {

    private final ScreenRepository screenRepository;

    public ScreenSyncService(ScreenRepository screenRepository) {
        this.screenRepository = screenRepository;
    }

    @Transactional
    public SyncResult upsertScreens(List<ScreenUpsertRequest> payload) {
        int inserted = 0;
        int updated = 0;
        for (ScreenUpsertRequest r : payload) {
            String code = r.getScreenCode();
            Screen s = screenRepository.findByScreenCode(code).orElse(null);
            if (s == null) {
                s = new Screen();
                s.setId(UUID.randomUUID());
                s.setCreatedAt(OffsetDateTime.now());
                inserted++;
            } else {
                updated++;
            }
            s.setScreenCode(code);
            s.setPath(r.getPath());
            s.setBasePath(r.getBasePath());
            s.setTitle(r.getTitle());
            s.setIcon(r.getIcon());
            s.setOrdering(r.getOrdering());
            s.setParentCode(r.getParentCode());
            s.setIsMenu(Boolean.TRUE.equals(r.getIsMenu()));
            s.setIsPublic(Boolean.TRUE.equals(r.getIsPublic()));
            s.setIsActive(Boolean.TRUE.equals(r.getIsActive()));
            s.setUpdatedAt(OffsetDateTime.now());
            screenRepository.save(s);
        }
        return new SyncResult(inserted, updated);
    }

    public static class SyncResult {
        private final int inserted;
        private final int updated;
        public SyncResult(int inserted, int updated) {
            this.inserted = inserted;
            this.updated = updated;
        }
        public int getInserted() { return inserted; }
        public int getUpdated() { return updated; }
    }
}

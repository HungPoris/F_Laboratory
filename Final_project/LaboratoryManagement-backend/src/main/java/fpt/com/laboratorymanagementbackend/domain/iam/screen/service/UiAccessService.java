package fpt.com.laboratorymanagementbackend.domain.iam.screen.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

@Service
public class UiAccessService {

    private final JdbcTemplate jdbc;
    private final ObjectMapper om;

    public UiAccessService(JdbcTemplate jdbc, ObjectMapper om) {
        this.jdbc = jdbc;
        this.om = om;
    }

    public List<String> getAccessibleScreens(UUID userId) {
        String sql = "SELECT iamservice_db.fn_accessible_screens(?)";
        String json = jdbc.queryForObject(sql, String.class, userId);
        try {
            JsonNode root = om.readTree(json);
            JsonNode arr = root.get("accessible_screens");
            List<String> out = new ArrayList<>();
            if (arr != null && arr.isArray()) {
                for (JsonNode n : arr) out.add(n.asText());
            }
            return out;
        } catch (Exception ex) {
            throw new RuntimeException(ex);
        }
    }

    public boolean canAccessBasePath(UUID userId, String basePath) {
        String sql = "SELECT iamservice_db.fn_can_access_base_path(?, ?)";
        Boolean allowed = jdbc.queryForObject(sql, Boolean.class, userId, basePath);
        return Boolean.TRUE.equals(allowed);
    }

    public JsonNode getUserRoutes(UUID userId) {
        String sql = "SELECT jsonb_agg(jsonb_build_object('screen_code', screen_code, 'path', path, 'base_path', base_path, 'title', title, 'icon', icon, 'ordering', ordering, 'is_menu', is_menu)) AS menu " +
                "FROM iamservice_db.v_user_allowed_screens v WHERE v.user_id = ?";
        String json = jdbc.queryForObject(sql, String.class, userId);
        try {
            if (json == null) return om.createObjectNode();
            return om.readTree("{\"menu\":" + json + "}");
        } catch (Exception ex) {
            throw new RuntimeException(ex);
        }
    }

    public List<String> getActionsForScreen(UUID userId, String screenCode) {
        String sql = "SELECT iamservice_db.fn_user_actions_for_screen(?, ?)";
        String json = jdbc.queryForObject(sql, String.class, userId, screenCode);
        try {
            JsonNode root = om.readTree(json);
            JsonNode actions = root.get("actions");
            List<String> out = new ArrayList<>();
            if (actions != null && actions.isArray()) {
                for (JsonNode n : actions) out.add(n.asText());
            }
            return out;
        } catch (Exception ex) {
            throw new RuntimeException(ex);
        }
    }
}

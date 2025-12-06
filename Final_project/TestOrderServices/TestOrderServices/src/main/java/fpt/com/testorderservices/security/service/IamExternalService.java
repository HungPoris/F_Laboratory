package fpt.com.testorderservices.security.service;

import fpt.com.testorderservices.security.dto.InternalJwtVerifyRequest;
import fpt.com.testorderservices.security.dto.InternalJwtVerifyResponse;
import fpt.com.testorderservices.security.dto.InternalUserSummaryResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;

import java.util.*;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Slf4j
public class IamExternalService {

    private final RestTemplate restTemplate;

    @Value("${app.services.iam.url}")
    private String iamServiceUrl;

    @Value("${app.services.iam.api-key}")
    private String iamApiKey;

    @Value("${app.services.iam.api-key-header:X-API-KEY}")
    private String apiKeyHeader;

    // --- 1. Verify Token (Giữ nguyên) ---
    public InternalJwtVerifyResponse verifyToken(String token, String method, String uri) {
        try {
            String url = iamServiceUrl + "/internal/security/jwt/verify";
            InternalJwtVerifyRequest requestBody = InternalJwtVerifyRequest.builder().token(token).method(method).uri(uri).build();
            HttpHeaders headers = createInternalHeaders();
            HttpEntity<InternalJwtVerifyRequest> entity = new HttpEntity<>(requestBody, headers);

            ResponseEntity<Map> response = restTemplate.exchange(url, HttpMethod.POST, entity, Map.class);

            if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
                Map<String, Object> body = response.getBody();
                boolean isValid = Boolean.TRUE.equals(body.get("valid"));
                if (!isValid) return InternalJwtVerifyResponse.builder().valid(false).errorMessage((String) body.get("errorMessage")).build();

                String userId = (String) body.get("userId");
                String username = (String) body.get("username");
                List<String> finalAuthorities = new ArrayList<>();
                Object privilegesObj = body.get("privileges");
                if (privilegesObj instanceof List<?>) ((List<?>) privilegesObj).forEach(p -> finalAuthorities.add(p.toString()));

                return InternalJwtVerifyResponse.builder().valid(true).userId(userId).username(username).authorities(finalAuthorities).build();
            }
            return InternalJwtVerifyResponse.builder().valid(false).errorMessage("INVALID_RESPONSE").build();
        } catch (Exception e) {
            log.error("Error calling IAM Service verify: {}", e.getMessage());
            return InternalJwtVerifyResponse.builder().valid(false).errorMessage("IAM_SERVICE_ERROR").build();
        }
    }

    // --- 2. Batch Fetch Users (Thêm Log Debug) ---
    public Map<UUID, InternalUserSummaryResponse> getUsersInfo(List<UUID> userIds) {
        // LOG INPUT
        log.info("🔹 [IAM-CALL] getUsersInfo called with {} IDs.", userIds != null ? userIds.size() : 0);

        if (userIds == null || userIds.isEmpty()) {
            return new HashMap<>();
        }

        try {
            String url = iamServiceUrl + "/internal/security/users/batch-fetch";
            HttpHeaders headers = createInternalHeaders();

            List<UUID> uniqueIds = userIds.stream()
                    .filter(Objects::nonNull)
                    .distinct()
                    .collect(Collectors.toList());

            if (uniqueIds.isEmpty()) return new HashMap<>();

            // LOG REQUEST
            log.info("🚀 [IAM-CALL] Sending POST to: {}", url);
            log.info("📦 [IAM-CALL] Payload IDs: {}", uniqueIds);

            HttpEntity<List<UUID>> entity = new HttpEntity<>(uniqueIds, headers);

            // Sử dụng mảng [] để map JSON array
            ResponseEntity<InternalUserSummaryResponse[]> response = restTemplate.exchange(
                    url,
                    HttpMethod.POST,
                    entity,
                    InternalUserSummaryResponse[].class
            );

            // LOG RESPONSE
            log.info("✅ [IAM-CALL] Response Status: {}", response.getStatusCode());

            if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
                InternalUserSummaryResponse[] users = response.getBody();
                log.info("📦 [IAM-CALL] Received {} users from IAM", users.length);

                // Log chi tiết vài user đầu tiên để kiểm tra
                if (users.length > 0) {
                    log.info("   -> First User sample: ID={}, Name={}", users[0].getUserId(), users[0].getFullName());
                }

                Map<UUID, InternalUserSummaryResponse> userMap = new HashMap<>();
                for (InternalUserSummaryResponse u : users) {
                    userMap.put(u.getUserId(), u);
                }
                return userMap;
            } else {
                log.warn("⚠️ [IAM-CALL] Response body is NULL or Status not 2xx");
            }

        } catch (HttpClientErrorException e) {
            // Log lỗi client (400, 401, 403, 404)
            log.error("❌ [IAM-CALL] Client Error: {} - Body: {}", e.getStatusCode(), e.getResponseBodyAsString());
        } catch (Exception e) {
            // Log lỗi server/mạng (500, Connection refused)
            log.error("🔥 [IAM-CALL] Exception: {}", e.getMessage(), e);
        }
        return new HashMap<>();
    }

    private HttpHeaders createInternalHeaders() {
        HttpHeaders headers = new HttpHeaders();
        headers.set("Content-Type", "application/json");
        headers.set(apiKeyHeader, iamApiKey);
        headers.set("User-Agent", "TestOrderServices/1.0");
        return headers;
    }
}
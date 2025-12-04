package fpt.com.laboratorymanagementbackend.common.service;

public interface JwtBlacklistService {
    void blacklistToken(String jti, long ttlSeconds);
    boolean isBlacklisted(String jti);
    void recordTokenForUser(String userId, String jti, long ttlSeconds);
    void blacklistAllTokensForUser(String userId);
}

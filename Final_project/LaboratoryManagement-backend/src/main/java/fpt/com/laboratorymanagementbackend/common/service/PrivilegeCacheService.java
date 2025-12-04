package fpt.com.laboratorymanagementbackend.common.service;

import java.util.Set;

public interface PrivilegeCacheService {
    Set<String> getPrivileges(String userId);
    void putPrivileges(String userId, Set<String> privilegeCodes);
    void evict(String userId);
}

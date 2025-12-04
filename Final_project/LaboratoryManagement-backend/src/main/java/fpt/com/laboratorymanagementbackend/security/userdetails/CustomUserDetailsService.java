package fpt.com.laboratorymanagementbackend.security.userdetails;

import fpt.com.laboratorymanagementbackend.common.service.PrivilegeCacheService;
import fpt.com.laboratorymanagementbackend.domain.iam.role.entity.Privilege;
import fpt.com.laboratorymanagementbackend.domain.iam.role.repository.PrivilegeRepository;
import fpt.com.laboratorymanagementbackend.domain.iam.user.entity.User;
import fpt.com.laboratorymanagementbackend.domain.iam.user.repository.UserRepository;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.userdetails.*;
import org.springframework.stereotype.Service;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.transaction.annotation.Transactional;

import java.util.*;
import java.util.stream.Collectors;

@Service
public class CustomUserDetailsService implements UserDetailsService {
    private final UserRepository userRepository;
    private final PrivilegeCacheService privilegeCacheService;
    private final JdbcTemplate jdbcTemplate;
    private final PrivilegeRepository privilegeRepository;

    private static final String PRIVILEGE_ALL_CODE = "privilege.all";

    @Autowired
    public CustomUserDetailsService(UserRepository userRepository,
                                    PrivilegeCacheService privilegeCacheService,
                                    JdbcTemplate jdbcTemplate,
                                    PrivilegeRepository privilegeRepository) {
        this.userRepository = userRepository;
        this.privilegeCacheService = privilegeCacheService;
        this.jdbcTemplate = jdbcTemplate;
        this.privilegeRepository = privilegeRepository;
    }

    @Override
    public UserDetails loadUserByUsername(String usernameOrEmail) throws UsernameNotFoundException {
        return loadByUsernameOrEmail(usernameOrEmail)
                .orElseThrow(() -> new UsernameNotFoundException("User not found"));
    }

    @Transactional(readOnly = true)
    public Optional<UserPrincipal> loadByUsernameOrEmail(String usernameOrEmail) {
        Optional<User> maybe;
        try {
            maybe = userRepository.findByUsernameIgnoreCaseOrEmailIgnoreCase(usernameOrEmail, usernameOrEmail);
        } catch (NoSuchMethodError ex) {
            maybe = userRepository.findByUsernameIgnoreCase(usernameOrEmail)
                    .or(() -> userRepository.findByEmailIgnoreCase(usernameOrEmail));
        } catch (Throwable t) {
            maybe = userRepository.findByUsernameIgnoreCase(usernameOrEmail)
                    .or(() -> userRepository.findByEmailIgnoreCase(usernameOrEmail));
        }

        if (maybe.isEmpty()) {
            return Optional.empty();
        }

        User user = maybe.get();

        Set<String> roleCodes = user.getRoles().stream()
                .map(r -> r.getRoleCode())
                .collect(Collectors.toCollection(LinkedHashSet::new));

        String userIdStr = user.getUserId() != null ? user.getUserId().toString() : null;

        Set<String> privilegeCodes = null;
        if (userIdStr != null) {
            try {
                privilegeCodes = privilegeCacheService.getPrivileges(userIdStr);
            } catch (Exception ignore) {
                privilegeCodes = null;
            }
        }
        if (privilegeCodes == null || privilegeCodes.isEmpty()) {
            privilegeCodes = user.getRoles().stream()
                    .flatMap(r -> r.getPrivileges().stream())
                    .map(p -> p.getPrivilegeCode())
                    .collect(Collectors.toCollection(LinkedHashSet::new));
            if (userIdStr != null) {
                try {
                    privilegeCacheService.putPrivileges(userIdStr, privilegeCodes);
                } catch (Exception ignore) { }
            }
        }

        Set<String> effectivePrivileges = new LinkedHashSet<>(privilegeCodes);
        try {
            if (effectivePrivileges.contains(PRIVILEGE_ALL_CODE)) {
                List<Privilege> allPrivileges = privilegeRepository.findAll();
                for (Privilege p : allPrivileges) {
                    if (p != null && p.getPrivilegeCode() != null && !p.getPrivilegeCode().isBlank()) {
                        effectivePrivileges.add(p.getPrivilegeCode());
                    }
                }
                effectivePrivileges.add(PRIVILEGE_ALL_CODE);
            }
        } catch (Exception ignore) {
        }


        List<GrantedAuthority> authorities = new ArrayList<>();
        roleCodes.forEach(rc -> authorities.add(new SimpleGrantedAuthority("ROLE_" + rc)));

        for (String pc : effectivePrivileges) {
            if (pc == null || pc.isEmpty()) continue;
            authorities.add(new SimpleGrantedAuthority("PRIV:" + pc));
            authorities.add(new SimpleGrantedAuthority(pc));
        }

        List<String> screenActionAuthorities = Collections.emptyList();
        try {
            if (user.getUserId() != null) {
                String sql = "SELECT DISTINCT v.screen_code || ':' || v.action_code AS sa FROM iamservice_db.v_user_screen_actions v WHERE v.user_id = ?";
                screenActionAuthorities = jdbcTemplate.queryForList(sql, String.class, user.getUserId());
            }
        } catch (Exception ignore) {
            screenActionAuthorities = Collections.emptyList();
        }
        screenActionAuthorities.stream()
                .map(sa -> "SCREEN:" + sa)
                .map(SimpleGrantedAuthority::new)
                .forEach(authorities::add);

        UserPrincipal principal = new UserPrincipal(
                user.getUserId(),
                user.getUsername(),
                user.getPasswordHash(),
                user.getFullName(),
                user.getEmail(),
                roleCodes,
                effectivePrivileges,
                authorities,
                Boolean.TRUE.equals(user.getIsActive())
        );

        return Optional.of(principal);
    }
}

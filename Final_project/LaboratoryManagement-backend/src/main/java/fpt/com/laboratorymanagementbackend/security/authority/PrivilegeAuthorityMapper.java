package fpt.com.laboratorymanagementbackend.security.authority;

import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;

import java.util.List;
import java.util.stream.Collectors;

public class PrivilegeAuthorityMapper {

    public static List<GrantedAuthority> toPrivilegesAuthorities(List<String> privileges) {
        return privileges.stream()
                .map(p -> p == null ? null : (p.startsWith("PRIV:") ? p : "PRIV:" + p))
                .filter(s -> s != null && !s.isEmpty())
                .map(SimpleGrantedAuthority::new)
                .collect(Collectors.toList());
    }

    public static List<GrantedAuthority> toScreenActionAuthorities(List<String> screenActionAuthorities) {
        return screenActionAuthorities.stream()
                .map(SimpleGrantedAuthority::new)
                .collect(Collectors.toList());
    }
}

package fpt.com.laboratorymanagementbackend.security.userdetails;

import lombok.Getter;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.userdetails.UserDetails;
import java.util.*;
import java.util.stream.Collectors;

public class UserPrincipal implements UserDetails {
    @Getter
    private final UUID id;
    private final String username;
    private final String passwordHash;
    @Getter
    private final String email;
    @Getter
    private final String fullName;
    private final Set<String> roleCodes;
    private final Set<String> privilegeCodes;
    private final Collection<GrantedAuthority> authorities;
    private final boolean enabled;

    public UserPrincipal(UUID id,
                         String username,
                         String passwordHash,
                         String fullName,
                         String email,
                         Set<String> roleCodes,
                         Set<String> privilegeCodes,
                         Collection<GrantedAuthority> authorities,
                         boolean enabled) {
        this.id = id;
        this.username = username;
        this.passwordHash = passwordHash;
        this.fullName = fullName;
        this.email = email;
        this.roleCodes = roleCodes == null ? Set.of() : Set.copyOf(roleCodes);
        this.privilegeCodes = privilegeCodes == null ? Set.of() : Set.copyOf(privilegeCodes);
        this.authorities = authorities == null ? List.of() : List.copyOf(authorities);
        this.enabled = enabled;
    }

    public UserPrincipal(UUID id, String username, String passwordHash, String email,
                         Set<String> roleCodes, Set<String> privilegeCodes,
                         Collection<GrantedAuthority> authorities, boolean enabled) {
        this(id, username, passwordHash, null, email, roleCodes, privilegeCodes, authorities, enabled);
    }

    public List<String> getRolesAsList() {
        return roleCodes.stream().collect(Collectors.toUnmodifiableList());
    }

    public List<String> getPrivilegesAsList() {
        return privilegeCodes.stream().collect(Collectors.toUnmodifiableList());
    }

    public Set<String> getRoles() {
        return roleCodes;
    }

    public Set<String> getPrivileges() {
        return privilegeCodes;
    }

    @Override
    public Collection<? extends GrantedAuthority> getAuthorities() {
        return authorities;
    }

    @Override
    public String getPassword() {
        return passwordHash;
    }

    @Override
    public String getUsername() {
        return username;
    }

    @Override
    public boolean isAccountNonExpired() {
        return true;
    }

    @Override
    public boolean isAccountNonLocked() {
        return true;
    }

    @Override
    public boolean isCredentialsNonExpired() {
        return true;
    }

    @Override
    public boolean isEnabled() {
        return enabled;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        UserPrincipal that = (UserPrincipal) o;
        return id.equals(that.id);
    }

    @Override
    public int hashCode() {
        return Objects.hash(id);
    }
}

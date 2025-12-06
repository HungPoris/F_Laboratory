package fpt.com.testorderservices.common.config;

import org.springframework.core.convert.converter.Converter;
import org.springframework.security.authentication.AbstractAuthenticationToken;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.security.oauth2.server.resource.authentication.JwtGrantedAuthoritiesConverter;
import org.springframework.stereotype.Component;

import java.util.*;
import java.util.stream.Collectors;
import java.util.stream.Stream;

/**
 * ✅ JwtAuthConverter
 * --------------------
 * - Đọc các claim từ JWT (bao gồm 'authorities', 'SCREEN:*', 'PRIV:*', v.v.)
 * - Chuyển chúng thành GrantedAuthority để Spring Security xử lý
 * - Giúp @PreAuthorize() có thể nhận diện quyền truy cập (permission-based access control)
 * - Gán userId chính là giá trị từ claim 'sub' (subject) thay vì 'jti'
 */
@Component
public class JwtAuthConverter implements Converter<Jwt, AbstractAuthenticationToken> {

    private final JwtGrantedAuthoritiesConverter jwtGrantedAuthoritiesConverter;

    public JwtAuthConverter() {
        this.jwtGrantedAuthoritiesConverter = new JwtGrantedAuthoritiesConverter();
    }

    @Override
    public AbstractAuthenticationToken convert(Jwt jwt) {
        // 🟢 1️⃣ Lấy quyền mặc định từ scope/scp
        Collection<GrantedAuthority> authorities =
                Optional.ofNullable(jwtGrantedAuthoritiesConverter.convert(jwt))
                        .orElse(Collections.emptyList());

        // 🟢 2️⃣ Lấy quyền tùy chỉnh từ claim 'authorities'
        List<String> customAuthorities = jwt.getClaimAsStringList("authorities");

        if (customAuthorities != null && !customAuthorities.isEmpty()) {
            // Chỉ lấy những quyền hợp lệ (loại bỏ null hoặc rỗng)
            List<GrantedAuthority> extraAuthorities = customAuthorities.stream()
                    .filter(Objects::nonNull)
                    .filter(auth -> !auth.isBlank())
                    .map(SimpleGrantedAuthority::new)
                    .collect(Collectors.toList());

            // Gộp quyền mặc định + quyền tùy chỉnh
            authorities = Stream.concat(authorities.stream(), extraAuthorities.stream())
                    .collect(Collectors.toSet()); // loại bỏ trùng
        }

        // 🟢 3️⃣ SỬA LẠI: Xác định principal (là userId)
        // 'sub' là chuẩn JWT chứa User ID cố định.
        // 'jti' là ID của token (random mỗi lần login), KHÔNG dùng làm User ID.
        String userId = jwt.getClaimAsString("sub");

        // Fallback: Một số Identity Provider dùng 'user_id' thay vì 'sub'
        if (userId == null || userId.isBlank()) {
            userId = jwt.getClaimAsString("user_id");
        }

        if (userId == null || userId.isBlank()) {
            throw new IllegalStateException("JWT missing claim 'sub' or 'user_id' - cannot determine userId");
        }

        return new JwtAuthenticationToken(jwt, authorities, userId);
    }
}
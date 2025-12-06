package fpt.com.testorderservices.common.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.web.SecurityFilterChain;

import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;


@Configuration
@EnableMethodSecurity // Bật bảo mật ở cấp độ phương thức (quan trọng cho @PreAuthorize)
public class SecurityConfig {

    @Value("${jwt.secret}")
    private String jwtSecret;

    // Inject converter (file mới ở bước 3)
    private final JwtAuthConverter jwtAuthConverter;

    // Cập nhật constructor
    public SecurityConfig(JwtAuthConverter jwtAuthConverter) {
        this.jwtAuthConverter = jwtAuthConverter;
    }

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
                // Tắt CSRF (giống backend)
                .csrf(csrf -> csrf.disable())
                // Sử dụng cấu hình CORS từ WebConfig của bạn
                .cors(cors -> {})
                // Cấu hình session là STATELESS (giống backend)
                .sessionManagement(session -> session
                        .sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                // Cấu hình phân quyền request
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers("/ws/**").permitAll()
                        .requestMatchers("/topic/**").permitAll()
                        .requestMatchers("/app/**").permitAll()
                        // Yêu cầu tất cả các request đến /api/** phải được xác thực
                        .requestMatchers("/api/**").authenticated()
                        // Cho phép các request khác (nếu có)
                        .anyRequest().permitAll()
                )
                // Kích hoạt xác thực JWT
                .oauth2ResourceServer(oauth2 -> oauth2
                        .jwt(jwt -> jwt
                                .decoder(jwtDecoder())
                                // Báo cho Spring biết dùng converter này để đọc quyền
                                .jwtAuthenticationConverter(jwtAuthConverter)
                        )
                );
        return http.build();
    }

    @Bean
    public JwtDecoder jwtDecoder() {
        // Sử dụng secret key từ application.properties để giải mã token
        SecretKeySpec secretKey = new SecretKeySpec(jwtSecret.getBytes(StandardCharsets.UTF_8), "MAC-SHA-256");
        // Cấu hình decoder để kiểm tra token
        return NimbusJwtDecoder.withSecretKey(secretKey).build();
    }
}
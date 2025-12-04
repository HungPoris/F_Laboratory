package fpt.com.laboratorymanagementbackend.security.config;

import fpt.com.laboratorymanagementbackend.common.service.JwtBlacklistService;
import fpt.com.laboratorymanagementbackend.security.apikey.ApiKeyAuthenticationFilter;
import fpt.com.laboratorymanagementbackend.security.cloudflare.CloudflareClientResolver;
import fpt.com.laboratorymanagementbackend.security.jwt.JwtAuthenticationFilter;
import fpt.com.laboratorymanagementbackend.security.jwt.JwtUtil;
import fpt.com.laboratorymanagementbackend.security.ratelimit.RateLimitFilter;
import fpt.com.laboratorymanagementbackend.security.ratelimit.RateLimitService;
import fpt.com.laboratorymanagementbackend.security.userdetails.CustomUserDetailsService;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.config.annotation.authentication.configuration.AuthenticationConfiguration;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.argon2.Argon2PasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.filter.CorsFilter;

import java.nio.charset.StandardCharsets;
import java.util.Set;

@Configuration
@EnableMethodSecurity
public class SecurityConfig {

    private final JwtUtil jwtUtil;
    private final CustomUserDetailsService uds;
    private final JwtBlacklistService jwtBlacklistService;
    private final CloudflareClientResolver resolver;
    private final ApiKeyAuthenticationFilter apiKeyAuthenticationFilter;

    @Value("${app.redis.key-prefix:prod}")
    private String redisKeyPrefix;

    @Value("${security.rate.auth.limit:20}")
    private int authRateLimit;

    @Value("${security.rate.auth.window-seconds:60}")
    private int authRateWindow;

    @Value("${app.jwt.blacklist.prefix:iam:jwt:blacklist:}")
    private String jwtBlacklistPrefix;

    @Value("${app.jwt.user.tokens.prefix:iam:jwt:user:}")
    private String userTokensPrefix;

    public SecurityConfig(JwtUtil jwtUtil,
                          CustomUserDetailsService uds,
                          JwtBlacklistService jwtBlacklistService,
                          CloudflareClientResolver resolver,
                          ApiKeyAuthenticationFilter apiKeyAuthenticationFilter) {
        this.jwtUtil = jwtUtil;
        this.uds = uds;
        this.jwtBlacklistService = jwtBlacklistService;
        this.resolver = resolver;
        this.apiKeyAuthenticationFilter = apiKeyAuthenticationFilter;
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new Argon2PasswordEncoder(16, 32, 1, 1 << 12, 3);
    }

    @Bean
    public AuthenticationManager authenticationManager(AuthenticationConfiguration cfg) throws Exception {
        return cfg.getAuthenticationManager();
    }

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http,
                                           CorsConfigurationSource corsConfigurationSource,
                                           RateLimitService rateLimitService,
                                           StringRedisTemplate stringRedisTemplate) throws Exception {

        JwtAuthenticationFilter jwtFilter = new JwtAuthenticationFilter(
                jwtUtil,
                uds,
                stringRedisTemplate,
                jwtBlacklistPrefix,
                jwtBlacklistService,
                userTokensPrefix
        );

        RateLimitFilter rateLimitFilter = new RateLimitFilter(
                rateLimitService,
                authRateLimit,
                authRateWindow,
                Set.of("/api/v1/auth", "/auth/otp"),
                resolver,
                redisKeyPrefix
        );

        http
                .cors(c -> c.configurationSource(corsConfigurationSource))
                .csrf(csrf -> csrf.disable())
                .sessionManagement(sm -> sm.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .exceptionHandling(ex -> ex
                        .authenticationEntryPoint((req, res, e) -> {
                            res.setStatus(HttpStatus.UNAUTHORIZED.value());
                            res.setContentType("application/json");
                            res.getOutputStream().write("{\"error\":\"unauthorized\"}".getBytes(StandardCharsets.UTF_8));
                        })
                        .accessDeniedHandler((req, res, e) -> {
                            res.setStatus(HttpStatus.FORBIDDEN.value());
                            res.setContentType("application/json");
                            res.getOutputStream().write("{\"error\":\"forbidden\"}".getBytes(StandardCharsets.UTF_8));
                        })
                )
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers(HttpMethod.OPTIONS, "/**").permitAll()
                        .requestMatchers("/api/v1/auth/**", "/auth/otp/**").permitAll()
                        .requestMatchers("/actuator/health", "/actuator/info", "/actuator/prometheus").permitAll()
                        .requestMatchers("/api/v1/screens/**").permitAll()
                        .requestMatchers("/internal/**").permitAll()
                        .anyRequest().authenticated()
                )
                .addFilterAfter(rateLimitFilter, CorsFilter.class)
                .addFilterBefore(apiKeyAuthenticationFilter, UsernamePasswordAuthenticationFilter.class)
                .addFilterBefore(jwtFilter, UsernamePasswordAuthenticationFilter.class)
                .httpBasic(h -> h.disable())
                .formLogin(f -> f.disable())
                .logout(l -> l.disable());

        return http.build();
    }
}

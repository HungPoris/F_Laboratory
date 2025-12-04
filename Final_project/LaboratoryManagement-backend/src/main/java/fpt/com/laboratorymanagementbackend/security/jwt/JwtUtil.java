package fpt.com.laboratorymanagementbackend.security.jwt;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.SignatureAlgorithm;
import io.jsonwebtoken.security.Keys;
import jakarta.annotation.PostConstruct;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.stereotype.Component;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Collection;
import java.util.Date;
import java.util.List;
import java.util.stream.Collectors;

@Component
public class JwtUtil {

    @Value("${app.jwt.secret}")
    private String jwtSecret;

    @Value("${app.jwt.issuer:laboratory-management}")
    private String issuer;

    @Value("${app.jwt.access.minutes:15}")
    private int accessMinutes;

    private SecretKey key;

    @PostConstruct
    public void init() {
        byte[] bytes = jwtSecret.getBytes(StandardCharsets.UTF_8);
        this.key = Keys.hmacShaKeyFor(bytes);
    }

    public String generateTokenWithJti(String subject, String jti, Collection<? extends GrantedAuthority> authorities) {
        Instant now = Instant.now();
        Instant exp = now.plus(accessMinutes, ChronoUnit.MINUTES);
        List<String> authList = authorities != null
                ? authorities.stream().map(GrantedAuthority::getAuthority).collect(Collectors.toList())
                : List.of();
        return Jwts.builder()
                .setIssuer(issuer)
                .setSubject(subject)
                .setId(jti)
                .setIssuedAt(Date.from(now))
                .setExpiration(Date.from(exp))
                .claim("authorities", authList)
                .signWith(key, SignatureAlgorithm.HS256)
                .compact();
    }

    public String generateTokenWithJti(String subject, String jti) {
        return generateTokenWithJti(subject, jti, null);
    }

    public String generateAccessToken(String subject, String jti, Collection<? extends GrantedAuthority> authorities) {
        return generateTokenWithJti(subject, jti, authorities);
    }

    public String generateAccessToken(String subject, String jti) {
        return generateTokenWithJti(subject, jti, null);
    }

    public String generateAccessToken(String subject) {
        String jti = java.util.UUID.randomUUID().toString();
        return generateTokenWithJti(subject, jti, null);
    }

    public Claims parseClaims(String token) {
        return Jwts.parserBuilder().setSigningKey(key).build().parseClaimsJws(token).getBody();
    }

    public long getAccessTokenTtlSeconds() {
        return accessMinutes * 60L;
    }
}

package fpt.com.testorderservices.security.filter;

import fpt.com.testorderservices.security.dto.InternalJwtVerifyResponse;
import fpt.com.testorderservices.security.service.IamExternalService;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.Collections;
import java.util.List;
import java.util.stream.Collectors;

@Component
@RequiredArgsConstructor
public class IamAuthenticationFilter extends OncePerRequestFilter {

    private final IamExternalService iamExternalService;

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {

        String token = getTokenFromRequest(request);

        if (StringUtils.hasText(token)) {
            // Gọi sang IAM để verify
            InternalJwtVerifyResponse iamResponse = iamExternalService.verifyToken(token, request.getMethod(), request.getRequestURI());

            if (iamResponse != null && iamResponse.isValid()) {
                // Convert danh sách quyền từ String sang GrantedAuthority
                List<GrantedAuthority> authorities = iamResponse.getAuthorities() != null
                        ? iamResponse.getAuthorities().stream().map(SimpleGrantedAuthority::new).collect(Collectors.toList())
                        : Collections.emptyList();
                logger.info("User: " + iamResponse.getUsername());
                logger.info("Authorities received: " + authorities);
                // Tạo đối tượng Authentication (sử dụng userId làm principal)
                UsernamePasswordAuthenticationToken authentication = new UsernamePasswordAuthenticationToken(
                        iamResponse.getUserId(), // Principal: User ID
                        null,                    // Credentials: null (đã xác thực)
                        authorities              // Authorities
                );

                authentication.setDetails(new WebAuthenticationDetailsSource().buildDetails(request));

                // Lưu vào Security Context
                SecurityContextHolder.getContext().setAuthentication(authentication);
            } else {
                // Token không hợp lệ hoặc hết hạn
                logger.warn("Token validation failed by IAM: " + (iamResponse != null ? iamResponse.getErrorMessage() : "Unknown error"));
            }
        }

        filterChain.doFilter(request, response);
    }

    private String getTokenFromRequest(HttpServletRequest request) {
        String bearerToken = request.getHeader("Authorization");
        if (StringUtils.hasText(bearerToken) && bearerToken.startsWith("Bearer ")) {
            return bearerToken.substring(7);
        }
        return null;
    }
}
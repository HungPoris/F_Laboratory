package fpt.com.laboratorymanagementbackend.security.apikey;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Component;
import org.springframework.util.AntPathMatcher;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.Arrays;
import java.util.List;
import java.util.stream.Collectors;

@Component
public class ApiKeyAuthenticationFilter extends OncePerRequestFilter {

    private final ApiKeyService apiKeyService;
    private final AntPathMatcher pathMatcher = new AntPathMatcher();
    private final List<String> protectedPatterns;

    public ApiKeyAuthenticationFilter(
            ApiKeyService apiKeyService,
            @Value("${security.service-api.patterns:/internal/**}") String patternCsv
    ) {
        this.apiKeyService = apiKeyService;
        this.protectedPatterns = Arrays.stream(patternCsv.split(","))
                .map(String::trim)
                .filter(s -> !s.isEmpty())
                .collect(Collectors.toList());
    }

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain
    ) throws ServletException, IOException {

        String path = request.getRequestURI();

        boolean isProtected = protectedPatterns.stream()
                .anyMatch(p -> pathMatcher.match(p, path));

        if (!isProtected) {
            filterChain.doFilter(request, response);
            return;
        }

        String headerName = apiKeyService.getHeaderName();
        String expectedKey = apiKeyService.getApiKey();
        String providedKey = request.getHeader(headerName);

        if (providedKey == null || !providedKey.equals(expectedKey)) {
            response.setStatus(HttpStatus.UNAUTHORIZED.value());
            response.getWriter().write("Invalid or missing API key");
            return;
        }

        filterChain.doFilter(request, response);
    }
}

//package fpt.com.testorderservices.common.apikey;
//
//import fpt.com.testorderservices.common.apikey.ApiKeyProperties;
//import fpt.com.testorderservices.common.apikey.ApiKeyService;
//import jakarta.servlet.FilterChain;
//import jakarta.servlet.ServletException;
//import jakarta.servlet.http.HttpServletRequest;
//import jakarta.servlet.http.HttpServletResponse;
//import org.springframework.util.AntPathMatcher;
//import org.springframework.web.filter.OncePerRequestFilter;
//import java.io.IOException;
//
//public class ApiKeyFilter extends OncePerRequestFilter {
//    private final ApiKeyProperties props;
//    private final ApiKeyService service;
//    private final AntPathMatcher matcher = new AntPathMatcher();
//
//    public ApiKeyFilter(ApiKeyProperties props, ApiKeyService service) {
//        this.props = props;
//        this.service = service;
//    }
//
//    @Override
//    protected boolean shouldNotFilter(HttpServletRequest request) {
//        String p = request.getRequestURI();
//        if ("OPTIONS".equalsIgnoreCase(request.getMethod())) return true;
//        for (String pat : props.getIgnore()) if (matcher.match(pat.trim(), p)) return true;
//        return false;
//    }
//
//    @Override
//    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
//            throws ServletException, IOException {
//        String k = request.getHeader(props.getHeader());
//        if (!service.isValid(k)) {
//            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
//            response.setContentType("application/json");
//            response.getWriter().write("{\"error\":\"invalid_api_key\"}");
//            return;
//        }
//        chain.doFilter(request, response);
//    }
//}
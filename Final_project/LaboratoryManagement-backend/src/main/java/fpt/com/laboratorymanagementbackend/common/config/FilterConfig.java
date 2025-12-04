package fpt.com.laboratorymanagementbackend.common.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Bean;
import org.springframework.core.env.Environment;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import java.util.Set;
import java.util.LinkedHashSet;
import fpt.com.laboratorymanagementbackend.security.filter.CloudflareTrustFilter;
import fpt.com.laboratorymanagementbackend.security.ratelimit.RateLimitFilter;
import fpt.com.laboratorymanagementbackend.security.ratelimit.RateLimitService;
import fpt.com.laboratorymanagementbackend.security.cloudflare.CloudflareClientResolver;

@Configuration
public class FilterConfig {

    @Bean
    public CloudflareClientResolver cloudflareClientResolver(Environment env) {
        boolean enabled = Boolean.parseBoolean(env.getProperty("cloudflare.trust.enabled", "false"));
        String hdr = env.getProperty("cloudflare.trust.headers.client-ip", "CF-Connecting-IP");
        return new CloudflareClientResolver(enabled, hdr);
    }

    @Bean
    public FilterRegistrationBean<CloudflareTrustFilter> cloudflareFilter(Environment env) {
        boolean enabled = Boolean.parseBoolean(env.getProperty("cloudflare.trust.enabled", "false"));
        String hdr = env.getProperty("cloudflare.trust.headers.client-ip", "CF-Connecting-IP");
        CloudflareTrustFilter f = new CloudflareTrustFilter(enabled, hdr);
        FilterRegistrationBean<CloudflareTrustFilter> reg = new FilterRegistrationBean<>(f);
        reg.setOrder(-110);
        reg.addUrlPatterns("/*");
        return reg;
    }

    @Bean
    public FilterRegistrationBean<RateLimitFilter> rateLimitFilter(
            Environment env,
            RateLimitService rateLimitService,
            CloudflareClientResolver resolver) {
        int maxRequests = Integer.parseInt(env.getProperty("security.rate.auth.limit", "20"));
        int windowSeconds = Integer.parseInt(env.getProperty("security.rate.auth.window-seconds", "60"));
        String redisKeyPrefix = env.getProperty("app.redis.key-prefix", "app");

        Set<String> paths = new LinkedHashSet<>();
        paths.add("/api/v1/auth");
        paths.add("/auth/otp");

        RateLimitFilter f = new RateLimitFilter(
                rateLimitService,
                maxRequests,
                windowSeconds,
                paths,
                resolver,
                redisKeyPrefix
        );

        FilterRegistrationBean<RateLimitFilter> reg = new FilterRegistrationBean<>(f);
        reg.setOrder(-101);
        reg.addUrlPatterns("/api/v1/*", "/auth/otp/*");
        return reg;
    }
}

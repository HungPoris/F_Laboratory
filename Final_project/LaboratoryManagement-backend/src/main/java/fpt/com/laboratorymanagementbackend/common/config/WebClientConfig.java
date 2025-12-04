package fpt.com.laboratorymanagementbackend.common.config;

import fpt.com.laboratorymanagementbackend.security.apikey.ApiKeyService;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestTemplate;

@Configuration
public class WebClientConfig {

    @Bean
    public RestTemplate restTemplate(ApiKeyService apiKeyService) {
        RestTemplate restTemplate = new RestTemplate();
        restTemplate.getInterceptors().add((request, body, execution) -> {
            request.getHeaders().set(apiKeyService.getHeaderName(), apiKeyService.getApiKey());
            return execution.execute(request, body);
        });
        return restTemplate;
    }
}

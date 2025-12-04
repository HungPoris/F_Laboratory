package fpt.com.laboratorymanagementbackend.security.apikey;

import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Service;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;

@Service
public class ApiKeyService {

    private final String headerName;
    private final String apiKey;

    public ApiKeyService() {
        String[] pair = loadFromFile();
        this.headerName = pair[0];
        this.apiKey = pair[1];
    }

    private String[] loadFromFile() {
        String defaultHeader = "X-API-KEY";
        String header = defaultHeader;
        String key = null;

        ClassPathResource resource = new ClassPathResource("API_Key.text");

        try (BufferedReader reader =
                     new BufferedReader(new InputStreamReader(resource.getInputStream()))) {

            String line = reader.readLine();
            if (line == null || line.trim().isEmpty()) {
                throw new IllegalStateException("API_Key.text is empty");
            }

            int idx = line.indexOf(':');
            if (idx != -1) {
                header = line.substring(0, idx).trim();
                key = line.substring(idx + 1).trim();
            } else {
                key = line.trim();
            }

        } catch (IOException e) {
            throw new IllegalStateException("Cannot read API_Key.text", e);
        }

        if (key == null || key.isEmpty()) {
            throw new IllegalStateException("API key value is empty");
        }

        return new String[]{header, key};
    }

    public String getHeaderName() {
        return headerName;
    }

    public String getApiKey() {
        return apiKey;
    }
}

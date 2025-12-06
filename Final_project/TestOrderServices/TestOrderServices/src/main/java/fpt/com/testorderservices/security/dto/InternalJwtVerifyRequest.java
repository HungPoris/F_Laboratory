package fpt.com.testorderservices.security.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class InternalJwtVerifyRequest {
    private String token;
    private String method; // GET, POST, etc. (Tuỳ chọn nếu IAM cần check scope theo method)
    private String uri;    // (Tuỳ chọn)
}
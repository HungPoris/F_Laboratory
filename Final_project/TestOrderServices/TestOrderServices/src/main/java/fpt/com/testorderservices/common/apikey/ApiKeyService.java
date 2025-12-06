//package fpt.com.testorderservices.common.apikey;
//
//import org.springframework.stereotype.Service;
//
//import java.util.Map;
//
//@Service
//public class ApiKeyService {
//    private final Map<String,String> allowed;
//    public ApiKeyService(ApiKeyProperties props) { this.allowed = props.getAllowed(); }
//    public boolean isValid(String key) {
//        if (key == null) return false;
//        for (String v : allowed.values()) if (v.equals(key)) return true;
//        return false;
//    }
//}

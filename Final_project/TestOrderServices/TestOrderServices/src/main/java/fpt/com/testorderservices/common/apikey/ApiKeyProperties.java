//package fpt.com.testorderservices.common.apikey;
//
//
//import org.springframework.boot.context.properties.ConfigurationProperties;
//import java.util.*;
//
//@ConfigurationProperties(prefix = "app.apikey")
//public class ApiKeyProperties {
//    private String header = "X-API-KEY";
//    private Map<String,String> allowed = new HashMap<>();
//    private List<String> ignore = new ArrayList<>();
//    private String outboundTargetKey;
//
//    public String getHeader() { return header; }
//    public void setHeader(String header) { this.header = header; }
//    public Map<String, String> getAllowed() { return allowed; }
//    public void setAllowed(Map<String, String> allowed) { this.allowed = allowed; }
//    public List<String> getIgnore() { return ignore; }
//    public void setIgnore(List<String> ignore) { this.ignore = ignore; }
//    public String getOutboundTargetKey() { return outboundTargetKey; }
//    public void setOutboundTargetKey(String outboundTargetKey) { this.outboundTargetKey = outboundTargetKey; }
//}

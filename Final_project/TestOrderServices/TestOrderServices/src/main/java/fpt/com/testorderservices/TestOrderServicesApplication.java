package fpt.com.testorderservices;

//import fpt.com.testorderservices.common.apikey.ApiKeyProperties;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;


@EnableWebSecurity
@SpringBootApplication
//@EnableConfigurationProperties(ApiKeyProperties.class)
public class TestOrderServicesApplication {

    public static void main(String[] args) {
        SpringApplication.run(TestOrderServicesApplication.class, args);
        System.out.println("TestOrderServicesApplication started");
        System.out.println("TestOrderServicesApplication at 8080");
    }

}

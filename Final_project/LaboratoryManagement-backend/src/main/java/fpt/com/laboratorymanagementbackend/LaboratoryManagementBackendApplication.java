package fpt.com.laboratorymanagementbackend;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.event.EventListener;
import org.springframework.core.env.Environment;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.amqp.rabbit.annotation.EnableRabbit;


@SpringBootApplication
@EnableScheduling

public class LaboratoryManagementBackendApplication {

    private final Environment env;

    public LaboratoryManagementBackendApplication(Environment env) {
        this.env = env;
    }

    public static void main(String[] args) {
        System.setProperty("io.netty.noUnsafe", "true");
        SpringApplication.run(LaboratoryManagementBackendApplication.class, args);
    }

    @EventListener(ApplicationReadyEvent.class)
    public void onApplicationReady() {
        String port = env.getProperty("local.server.port", env.getProperty("server.port", "8080"));
        System.out.println("🚀 Laboratory Management API đã khởi chạy thành công! Port: " + port);
    }
}

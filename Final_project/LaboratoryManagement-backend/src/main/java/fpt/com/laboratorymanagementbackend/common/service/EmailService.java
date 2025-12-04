package fpt.com.laboratorymanagementbackend.common.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.ApplicationContext;
import org.springframework.core.io.Resource;
import org.springframework.stereotype.Service;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.thymeleaf.spring6.SpringTemplateEngine;
import org.thymeleaf.context.Context;
import org.thymeleaf.exceptions.TemplateProcessingException;
import jakarta.mail.internet.MimeMessage;

import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.HashMap;

@Service
public class EmailService {
    private final JavaMailSender mailSender;
    private final SpringTemplateEngine templateEngine;
    private final ApplicationContext applicationContext;
    private final Logger log = LoggerFactory.getLogger(EmailService.class);

    public EmailService(JavaMailSender mailSender, SpringTemplateEngine templateEngine, ApplicationContext applicationContext) {
        this.mailSender = mailSender;
        this.templateEngine = templateEngine;
        this.applicationContext = applicationContext;
    }

    @SuppressWarnings("unchecked")
    public void sendHtml(String to, String subject, String templateName, Map<String, Object> model) {
        String resourcePath = "classpath:templates/" + templateName + ".html";
        try {
            Resource resource = applicationContext.getResource(resourcePath);
            if (resource == null || !resource.exists()) {
                log.error("Email template not found on classpath: {}. Aborting sendHtml(to={}, template={})", resourcePath, to, templateName);
                return;
            }

            Map<String, Object> safe = model == null ? new HashMap<>() : new HashMap<>(model);
            Object nested = safe.get("model");
            Map<String, Object> modelVar = nested instanceof Map ? new HashMap<>((Map<String, Object>) nested) : safe;

            Context ctx = new Context();
            ctx.setVariable("model", modelVar);
            ctx.setVariables(modelVar);

            String html = templateEngine.process(templateName, ctx);

            MimeMessage message = mailSender.createMimeMessage();
            MimeMessageHelper helper = new MimeMessageHelper(
                    message,
                    MimeMessageHelper.MULTIPART_MODE_MIXED_RELATED,
                    StandardCharsets.UTF_8.name()
            );

            helper.setTo(to);
            helper.setSubject(subject);
            helper.setText(html, true);
            helper.setFrom("no-reply@flaboratory.cloud");

            mailSender.send(message);
            log.info("Email sent to {} using template {} (length={})", to, templateName, html != null ? html.length() : 0);
        } catch (TemplateProcessingException tpe) {
            log.error("Thymeleaf template error for template {}: {}. Aborting email send to {}.", templateName, tpe.getMessage(), to, tpe);
        } catch (Exception ex) {
            log.error("Failed to render/send email (to={}, template={}): {}", to, templateName, ex.getMessage(), ex);
            throw new RuntimeException(ex);
        }
    }
}

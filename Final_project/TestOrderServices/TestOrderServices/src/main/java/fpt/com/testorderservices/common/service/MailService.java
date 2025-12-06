package fpt.com.testorderservices.common.service;

import lombok.RequiredArgsConstructor;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Service;

@Service
@RequiredArgsConstructor
public class MailService {

    private final JavaMailSender mailSender;

    public void sendTestResultEmail(String toEmail, String patientName, String orderNumber) {
        String subject = "Your test results are now available";
        String body = String.format("""
                Dear %s,
                
                The test results for your order (Order ID: %s) have been successfully completed and reviewed.
                Please log in to the Laboratory Management System to view your detailed results.
                
                Best regards,
                Laboratory Department
                """, patientName, orderNumber);

        SimpleMailMessage message = new SimpleMailMessage();
        message.setTo(toEmail);
        message.setSubject(subject);
        message.setText(body);

        mailSender.send(message);
    }
}

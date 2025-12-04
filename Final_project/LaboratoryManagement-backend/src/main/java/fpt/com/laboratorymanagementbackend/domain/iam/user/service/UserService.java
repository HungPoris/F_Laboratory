package fpt.com.laboratorymanagementbackend.domain.iam.user.service;

import org.springframework.stereotype.Service;
import fpt.com.laboratorymanagementbackend.domain.iam.user.repository.UserRepository;
import fpt.com.laboratorymanagementbackend.domain.iam.user.entity.User;
import org.springframework.transaction.annotation.Transactional;
import java.util.UUID;
import org.springframework.security.crypto.password.PasswordEncoder;
import java.time.OffsetDateTime;

@Service
public class UserService {
    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    public UserService(UserRepository userRepository, PasswordEncoder passwordEncoder) {
        this.userRepository = userRepository;
        this.passwordEncoder = passwordEncoder;
    }
    @Transactional
    public void updatePassword(UUID userId, String rawPassword) {
        userRepository.findById(userId).ifPresent(u -> {
            u.setPasswordHash(passwordEncoder.encode(rawPassword));
            u.setPasswordUpdatedAt(OffsetDateTime.now());
            userRepository.save(u);
        });
    }
    @Transactional
    public User createUser(String username, String email, String rawPassword, String fullName) {
        if (userRepository.existsByUsernameIgnoreCase(username)) throw new IllegalArgumentException("username_exists");
        if (userRepository.existsByEmailIgnoreCase(email)) throw new IllegalArgumentException("email_exists");
        User u = new User();
        u.setUserId(UUID.randomUUID());
        u.setUsername(username);
        u.setEmail(email);
        u.setFullName(fullName == null ? "" : fullName);
        u.setPasswordHash(passwordEncoder.encode(rawPassword));
        u.setIsActive(true);
        u.setIsLocked(false);
        u.setCreatedAt(OffsetDateTime.now());
        u.setUpdatedAt(OffsetDateTime.now());
        User saved = userRepository.save(u);
        return saved;
    }
}

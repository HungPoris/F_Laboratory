package fpt.com.testorderservices.domain.masterdata.entity;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;
import java.util.UUID;

@Entity
@Table(name = "reagents")
@Getter
@Setter
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class Reagent {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    @Column(name = "reagent_id")
    private UUID id;

    @Column(name = "name", nullable = false, length = 200)
    private String name;

    @Column(name = "batch_number")
    private String batchNumber;

    @Column(name = "expiration_date")
    private LocalDateTime expirationDate;

    @Column(name = "supplier")
    private String supplier;
}
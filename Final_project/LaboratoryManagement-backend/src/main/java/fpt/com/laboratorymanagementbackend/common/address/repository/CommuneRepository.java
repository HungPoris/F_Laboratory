package fpt.com.laboratorymanagementbackend.common.address.repository;

import fpt.com.laboratorymanagementbackend.common.address.entity.Commune;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.*;
import org.springframework.data.repository.query.Param;

public interface CommuneRepository extends JpaRepository<Commune, String> {

    @Query(value = """
    SELECT * FROM iamservice_db.vn_commune c
    WHERE (:provinceCode IS NULL OR c.province_code = :provinceCode)
      AND (
        :q IS NULL OR
        lower(c.name) LIKE lower(concat('%', :q, '%')) OR
        lower(c.code) LIKE lower(concat('%', :q, '%'))
      )
  """,
            countQuery = """
    SELECT count(*) FROM iamservice_db.vn_commune c
    WHERE (:provinceCode IS NULL OR c.province_code = :provinceCode)
      AND (
        :q IS NULL OR
        lower(c.name) LIKE lower(concat('%', :q, '%')) OR
        lower(c.code) LIKE lower(concat('%', :q, '%'))
      )
  """,
            nativeQuery = true)
    Page<Commune> searchByProvinceAndQuery(@Param("provinceCode") String provinceCode,
                                           @Param("q") String q,
                                           Pageable pageable);

    @Query(value = """
    SELECT * FROM iamservice_db.vn_commune c
    WHERE (:provinceCode IS NULL OR c.province_code = :provinceCode)
      AND (:level IS NULL OR lower(c.administrative_level) = lower(:level))
      AND (
        :q IS NULL OR
        lower(c.name) LIKE lower(concat('%', :q, '%')) OR
        lower(c.english_name) LIKE lower(concat('%', :q, '%')) OR
        lower(c.code) LIKE lower(concat('%', :q, '%'))
      )
  """,
            countQuery = """
    SELECT count(*) FROM iamservice_db.vn_commune c
    WHERE (:provinceCode IS NULL OR c.province_code = :provinceCode)
      AND (:level IS NULL OR lower(c.administrative_level) = lower(:level))
      AND (
        :q IS NULL OR
        lower(c.name) LIKE lower(concat('%', :q, '%')) OR
        lower(c.english_name) LIKE lower(concat('%', :q, '%')) OR
        lower(c.code) LIKE lower(concat('%', :q, '%'))
      )
  """,
            nativeQuery = true)
    Page<Commune> search(@Param("provinceCode") String provinceCode,
                         @Param("level") String administrativeLevel,
                         @Param("q") String q,
                         Pageable pageable);
}
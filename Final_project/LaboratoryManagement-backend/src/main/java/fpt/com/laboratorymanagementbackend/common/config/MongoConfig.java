package fpt.com.laboratorymanagementbackend.common.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.convert.converter.Converter;
import org.springframework.data.mongodb.core.convert.MongoCustomConversions;

import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.Arrays;
import java.util.Date;
import java.util.List;

@Configuration
public class MongoConfig {

    @Bean
    public MongoCustomConversions mongoCustomConversions() {
        Converter<OffsetDateTime, Date> odtToDate = new Converter<OffsetDateTime, Date>() {
            @Override
            public Date convert(OffsetDateTime source) {
                if (source == null) return null;
                return Date.from(source.toInstant());
            }
        };

        Converter<Date, OffsetDateTime> dateToOdt = new Converter<Date, OffsetDateTime>() {
            @Override
            public OffsetDateTime convert(Date source) {
                if (source == null) return null;
                return OffsetDateTime.ofInstant(source.toInstant(), ZoneOffset.UTC);
            }
        };

        List<Converter<?, ?>> converters = Arrays.asList(odtToDate, dateToOdt);
        return new MongoCustomConversions(converters);
    }
}

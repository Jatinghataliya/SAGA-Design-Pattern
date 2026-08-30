package com.saga.order.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestTemplate;

@Configuration
public class AppConfig {

    /**
     * RestTemplate is used by the orchestrator to call downstream services.
     * In production you would use WebClient or a service-discovery-aware client.
     */
    @Bean
    public RestTemplate restTemplate() {
        return new RestTemplate();
    }
}

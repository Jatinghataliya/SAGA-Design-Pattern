# ─────────────────────────────────────────────
#  Stage 1: Build entire multi-module project
# ─────────────────────────────────────────────
FROM maven:3.9.6-eclipse-temurin-17 AS builder

WORKDIR /build

# Copy entire project (all modules needed for multi-module build)
COPY pom.xml .
COPY saga-commons/ saga-commons/
COPY order-service/ order-service/
COPY payment-service/ payment-service/
COPY inventory-service/ inventory-service/
COPY shipping-service/ shipping-service/
COPY choreography-commons/ choreography-commons/
COPY choreography-service/ choreography-service/

# Build all modules, skip tests (tested separately in CI)
RUN mvn install -DskipTests --no-transfer-progress

# ─────────────────────────────────────────────
#  Stage 2: Runtime
# ─────────────────────────────────────────────
FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

COPY --from=builder /build/order-service/target/order-service-*.jar app.jar

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"]

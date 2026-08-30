# ─────────────────────────────────────────────
#  Stage 1: Build
# ─────────────────────────────────────────────
FROM maven:3.9.6-eclipse-temurin-17 AS builder

WORKDIR /build

# Copy parent POM and saga-commons first (for layer caching)
COPY pom.xml .
COPY saga-commons/pom.xml saga-commons/pom.xml
COPY saga-commons/src saga-commons/src

# Copy inventory-service source
COPY inventory-service/pom.xml inventory-service/pom.xml
COPY inventory-service/src inventory-service/src

# Build saga-commons first, then inventory-service
RUN mvn -pl saga-commons install -DskipTests --no-transfer-progress
RUN mvn -pl inventory-service package -DskipTests --no-transfer-progress

# ─────────────────────────────────────────────
#  Stage 2: Runtime
# ─────────────────────────────────────────────
FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

COPY --from=builder /build/inventory-service/target/inventory-service-*.jar app.jar

EXPOSE 8082

ENTRYPOINT ["java", "-jar", "app.jar"]

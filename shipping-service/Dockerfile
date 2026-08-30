# ─────────────────────────────────────────────
#  Stage 1: Build
# ─────────────────────────────────────────────
FROM maven:3.9.6-eclipse-temurin-17 AS builder

WORKDIR /build

# Copy parent POM and saga-commons first (for layer caching)
COPY pom.xml .
COPY saga-commons/pom.xml saga-commons/pom.xml
COPY saga-commons/src saga-commons/src

# Copy shipping-service source
COPY shipping-service/pom.xml shipping-service/pom.xml
COPY shipping-service/src shipping-service/src

# Stub out sibling modules so parent POM validation passes
COPY order-service/pom.xml order-service/pom.xml
COPY payment-service/pom.xml payment-service/pom.xml
COPY inventory-service/pom.xml inventory-service/pom.xml
COPY choreography-commons/pom.xml choreography-commons/pom.xml
COPY choreography-service/pom.xml choreography-service/pom.xml

# Install parent POM into local .m2 so child modules can resolve it
RUN mvn -N install -DskipTests --no-transfer-progress
# Build saga-commons, then shipping-service
RUN mvn -pl saga-commons install -DskipTests --no-transfer-progress
RUN mvn -pl shipping-service package -DskipTests --no-transfer-progress

# ─────────────────────────────────────────────
#  Stage 2: Runtime
# ─────────────────────────────────────────────
FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

COPY --from=builder /build/shipping-service/target/shipping-service-*.jar app.jar

EXPOSE 8083

ENTRYPOINT ["java", "-jar", "app.jar"]

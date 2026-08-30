# ─────────────────────────────────────────────
#  Stage 1: Build
# ─────────────────────────────────────────────
FROM maven:3.9.6-eclipse-temurin-17 AS builder

WORKDIR /build

# Copy parent POM and choreography-commons first (for layer caching)
COPY pom.xml .
COPY choreography-commons/pom.xml choreography-commons/pom.xml
COPY choreography-commons/src choreography-commons/src

# Copy choreography-service source
COPY choreography-service/pom.xml choreography-service/pom.xml
COPY choreography-service/src choreography-service/src

# Stub out sibling modules so parent POM validation passes
COPY saga-commons/pom.xml saga-commons/pom.xml
COPY order-service/pom.xml order-service/pom.xml
COPY payment-service/pom.xml payment-service/pom.xml
COPY inventory-service/pom.xml inventory-service/pom.xml
COPY shipping-service/pom.xml shipping-service/pom.xml

# Build choreography-commons first, then choreography-service (skip tests in image build)
RUN mvn -pl choreography-commons install -DskipTests --no-transfer-progress
RUN mvn -pl choreography-service package -DskipTests --no-transfer-progress

# ─────────────────────────────────────────────
#  Stage 2: Runtime
# ─────────────────────────────────────────────
FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

# Copy the fat JAR from the build stage
COPY --from=builder /build/choreography-service/target/choreography-service-*.jar app.jar

EXPOSE 8090

ENTRYPOINT ["java", "-jar", "app.jar"]

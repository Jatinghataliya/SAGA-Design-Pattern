# ─────────────────────────────────────────────
#  Stage 1: Build
# ─────────────────────────────────────────────
FROM maven:3.9.6-eclipse-temurin-17 AS builder

WORKDIR /build

# Copy parent POM and saga-commons first (for layer caching)
COPY pom.xml .
COPY saga-commons/pom.xml saga-commons/pom.xml
COPY saga-commons/src saga-commons/src

# Copy order-service source
COPY order-service/pom.xml order-service/pom.xml
COPY order-service/src order-service/src

# Stub out sibling modules so parent POM validation passes
# (parent pom.xml lists all modules; Docker only copies 2 of them)
COPY payment-service/pom.xml payment-service/pom.xml
COPY inventory-service/pom.xml inventory-service/pom.xml
COPY shipping-service/pom.xml shipping-service/pom.xml
COPY choreography-commons/pom.xml choreography-commons/pom.xml
COPY choreography-service/pom.xml choreography-service/pom.xml

# Build saga-commons first, then order-service (skip tests in image build)
RUN mvn -pl saga-commons install -DskipTests --no-transfer-progress
RUN mvn -pl order-service package -DskipTests --no-transfer-progress

# ─────────────────────────────────────────────
#  Stage 2: Runtime
# ─────────────────────────────────────────────
FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

# Copy the fat JAR from the build stage
COPY --from=builder /build/order-service/target/order-service-*.jar app.jar

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "app.jar"]

FROM eclipse-temurin:21 AS builder
RUN apt-get update && apt-get install -y --no-install-recommends unzip curl && \
    curl -fsSL https://github.com/JetBrains/kotlin/releases/download/v2.1.10/kotlin-compiler-2.1.10.zip -o /tmp/kotlin.zip && \
    unzip -q /tmp/kotlin.zip -d /opt && \
    rm /tmp/kotlin.zip
ENV PATH="/opt/kotlinc/bin:${PATH}"
WORKDIR /app
COPY solution.kt .
RUN kotlinc solution.kt -include-runtime -d solution.jar

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=builder /app/solution.jar .
ENTRYPOINT ["java", "-jar", "solution.jar"]

FROM eclipse-temurin:21 AS builder
WORKDIR /app
COPY solution.java .
RUN javac solution.java

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=builder /app/*.class .
ENTRYPOINT ["java", "solution"]

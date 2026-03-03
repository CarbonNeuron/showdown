FROM eclipse-temurin:21 AS builder
RUN apt-get update && apt-get install -y --no-install-recommends curl && \
    curl -fsSL https://github.com/scala/scala3/releases/download/3.6.4/scala3-3.6.4.tar.gz -o /tmp/scala.tar.gz && \
    tar -xzf /tmp/scala.tar.gz -C /opt && \
    rm /tmp/scala.tar.gz
ENV PATH="/opt/scala3-3.6.4/bin:${PATH}"
WORKDIR /app
COPY solution.scala .
RUN scalac -deprecation solution.scala

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=builder /app/*.class /app/*.tasty /app/
COPY --from=builder /opt/scala3-3.6.4/maven2/org/scala-lang/scala-library/2.13.15/scala-library-2.13.15.jar /app/lib/
COPY --from=builder /opt/scala3-3.6.4/maven2/org/scala-lang/scala3-library_3/3.6.4/scala3-library_3-3.6.4.jar /app/lib/
ENTRYPOINT ["java", "-cp", "/app:/app/lib/*", "solution"]

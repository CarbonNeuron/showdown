FROM nimlang/nim:2.0.0 AS builder
WORKDIR /app
COPY solution.nim .
RUN nim c -d:release -d:danger --opt:speed -o:solution solution.nim

FROM debian:bookworm-slim
COPY --from=builder /app/solution /usr/local/bin/solution
ENTRYPOINT ["solution"]

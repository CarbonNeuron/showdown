FROM dlang2/ldc-ubuntu:latest AS builder
WORKDIR /app
COPY solution.d .
RUN ldc2 -O2 -release -of=solution solution.d

FROM debian:bookworm-slim
WORKDIR /app
COPY --from=builder /app/solution .
ENTRYPOINT ["./solution"]

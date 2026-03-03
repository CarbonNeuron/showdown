FROM rust:1.77-slim AS builder
WORKDIR /app
COPY solution.rs .
RUN rustc -O -o solution solution.rs

FROM debian:bookworm-slim
COPY --from=builder /app/solution /usr/local/bin/solution
ENTRYPOINT ["solution"]

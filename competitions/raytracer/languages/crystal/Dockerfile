FROM crystallang/crystal:latest AS builder
WORKDIR /app
COPY solution.cr .
RUN crystal build --release -o solution solution.cr

FROM debian:bookworm-slim
WORKDIR /app
COPY --from=builder /app/solution .
ENTRYPOINT ["./solution"]

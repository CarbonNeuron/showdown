FROM dart:stable AS builder
WORKDIR /app
COPY solution.dart .
RUN dart compile exe solution.dart -o solution

FROM debian:bookworm-slim
WORKDIR /app
COPY --from=builder /app/solution .
ENTRYPOINT ["./solution"]

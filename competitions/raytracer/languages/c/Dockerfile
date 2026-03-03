FROM gcc:14 AS builder
WORKDIR /app
COPY solution.c .
RUN gcc -O2 -o solution solution.c -lm

FROM debian:bookworm-slim
COPY --from=builder /app/solution /usr/local/bin/solution
ENTRYPOINT ["solution"]

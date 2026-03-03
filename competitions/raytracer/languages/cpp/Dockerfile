FROM gcc:14 AS builder
WORKDIR /app
COPY solution.cpp .
RUN g++ -O2 -static -o solution solution.cpp -lm

FROM debian:bookworm-slim
COPY --from=builder /app/solution /usr/local/bin/solution
ENTRYPOINT ["solution"]

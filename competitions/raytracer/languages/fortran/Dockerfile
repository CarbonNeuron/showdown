FROM gcc:14 AS builder
WORKDIR /app
COPY solution.f90 .
RUN gfortran -O2 -static -o solution solution.f90

FROM debian:bookworm-slim
COPY --from=builder /app/solution /usr/local/bin/solution
ENTRYPOINT ["solution"]

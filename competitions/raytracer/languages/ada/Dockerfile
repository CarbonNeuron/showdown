FROM debian:bookworm AS builder
RUN apt-get update && apt-get install -y --no-install-recommends gnat && rm -rf /var/lib/apt/lists/*
WORKDIR /build
COPY solution.adb .
RUN gnatmake -O2 -gnatp solution.adb -o solution -bargs -static -largs -static

FROM debian:bookworm-slim
COPY --from=builder /build/solution /solution
ENTRYPOINT ["/solution"]

FROM debian:bookworm-slim AS builder
RUN apt-get update && apt-get install -y wget xz-utils && \
    wget -q https://ziglang.org/download/0.13.0/zig-linux-x86_64-0.13.0.tar.xz && \
    tar xf zig-linux-x86_64-0.13.0.tar.xz && \
    mv zig-linux-x86_64-0.13.0 /opt/zig
WORKDIR /app
COPY solution.zig .
RUN /opt/zig/zig build-exe -OReleaseFast solution.zig --name solution

FROM debian:bookworm-slim
COPY --from=builder /app/solution /usr/local/bin/solution
ENTRYPOINT ["solution"]

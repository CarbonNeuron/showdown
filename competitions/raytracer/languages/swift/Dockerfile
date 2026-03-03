FROM swift:5.10 AS builder
WORKDIR /build
COPY solution.swift .
RUN swiftc -O -static-stdlib -o solution solution.swift

FROM debian:bookworm-slim
COPY --from=builder /build/solution /usr/local/bin/solution
ENTRYPOINT ["/usr/local/bin/solution"]

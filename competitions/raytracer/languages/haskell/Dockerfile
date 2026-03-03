FROM haskell:9.6 AS builder
WORKDIR /build
COPY solution.hs .
RUN ghc -O2 -o solution solution.hs

FROM debian:bookworm-slim
COPY --from=builder /build/solution /usr/local/bin/solution
ENTRYPOINT ["solution"]

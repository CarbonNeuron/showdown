FROM debian:bookworm AS build
RUN apt-get update && apt-get install -y --no-install-recommends fpc && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY solution.pas .
RUN fpc -O2 -osolution solution.pas

FROM debian:bookworm-slim
WORKDIR /app
COPY --from=build /app/solution .
ENTRYPOINT ["./solution"]

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends luajit && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY solution.lua .
ENTRYPOINT ["luajit", "solution.lua"]

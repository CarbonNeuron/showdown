FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends gawk && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY solution.awk .
ENTRYPOINT ["/bin/sh", "-c", "LC_ALL=C gawk -v w=$1 -v h=$2 -f solution.awk </dev/null", "sh"]

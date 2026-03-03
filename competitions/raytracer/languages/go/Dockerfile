FROM golang:1.22-bookworm AS builder
WORKDIR /app
COPY solution.go .
RUN go build -o solution solution.go

FROM debian:bookworm-slim
COPY --from=builder /app/solution /usr/local/bin/solution
ENTRYPOINT ["solution"]

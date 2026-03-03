FROM mcr.microsoft.com/dotnet/sdk:9.0 AS builder
WORKDIR /app
RUN dotnet new console -n raytracer --no-restore
WORKDIR /app/raytracer
COPY solution.cs Program.cs
RUN dotnet publish -c Release -o /app/out

FROM mcr.microsoft.com/dotnet/runtime:9.0
COPY --from=builder /app/out /app
ENTRYPOINT ["/app/raytracer"]

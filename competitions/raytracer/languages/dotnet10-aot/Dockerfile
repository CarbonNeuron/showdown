FROM mcr.microsoft.com/dotnet/sdk:10.0 AS builder
RUN apt-get update && apt-get install -y clang zlib1g-dev
WORKDIR /app
RUN dotnet new console -n raytracer --no-restore
WORKDIR /app/raytracer
COPY solution.cs Program.cs
RUN sed -i 's|</PropertyGroup>|<PublishAot>true</PublishAot><InvariantGlobalization>true</InvariantGlobalization></PropertyGroup>|' raytracer.csproj
RUN dotnet publish -c Release -o /app/out

FROM debian:bookworm-slim
COPY --from=builder /app/out/raytracer /usr/local/bin/raytracer
ENTRYPOINT ["raytracer"]

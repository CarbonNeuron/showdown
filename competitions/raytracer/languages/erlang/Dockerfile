FROM erlang:27-slim
WORKDIR /app
COPY solution.erl .
RUN erlc solution.erl
ENTRYPOINT ["erl", "-noshell", "-pa", "/app", "-run", "solution", "main", "-extra"]

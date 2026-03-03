FROM ocaml/opam:debian-12-ocaml-5.1 AS builder
WORKDIR /home/opam/build
COPY --chown=opam:opam solution.ml .
RUN opam exec -- ocamlfind ocamlopt -O2 -o solution solution.ml 2>/dev/null || opam exec -- ocamlopt -O2 -o solution solution.ml

FROM debian:bookworm-slim
COPY --from=builder /home/opam/build/solution /usr/local/bin/solution
ENTRYPOINT ["solution"]

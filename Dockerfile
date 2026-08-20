# Multi-stage build: compile with the full Go toolchain, ship only the
# static binary (Bahnpuls_Betrieb_und_Deployment, ADR-002/ADR-009).
FROM golang:1.26-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/collector ./cmd/collector
# statictool liegt im selben Image, laeuft aber als eigener Scheduled Task -- der
# Collector darf fuer einen Download nicht blockieren (Regel 3).
RUN CGO_ENABLED=0 go build -o /out/statictool ./cmd/statictool

FROM alpine:3.20
# ca-certificates: the collector calls the GTFS-RT feed over HTTPS.
# Alpine, not scratch/distroless: a future shell-based HEALTHCHECK on the
# heartbeat file (BPULS-022) needs a shell to run in.
# No apk tzdata package here — the binary embeds the timezone database
# itself via `import _ "time/tzdata"` (CLAUDE.md Regel 5, preferred over an
# image-level dependency), so the image stays independent of the base.
RUN apk add --no-cache ca-certificates

WORKDIR /app
COPY --from=build /out/collector ./collector
COPY --from=build /out/statictool ./statictool
COPY config ./config
# Healthcheck (BPULS-022) und fachliche Pruefung (BPULS-026) liegen als
# Shell-Skripte bei, damit beide dieselbe Definition von "gesund" benutzen wie
# das Runbook und nicht als Einzeiler in der Coolify-Oberflaeche verschwinden.
COPY deploy/healthcheck.sh deploy/pruefung.sh ./deploy/

# Raw data and the heartbeat file must live on the Coolify Persistent
# Volume, never in the container filesystem (CLAUDE.md Regel 2) — mount it
# at /data and point the collector there via environment variables:
#   BAHNPULS_DATA_DIR=/data/raw
#   BAHNPULS_HEARTBEAT_PATH=/data/heartbeat.json
# See deploy/README.md.

# Nur Lebendigkeit, nicht Sinnhaftigkeit -- die Begruendung steht in
# deploy/healthcheck.sh. start-period ist grosszuegig, weil ein Healthcheck,
# der beim Deployment nie gruen wird, den Container in eine Restart-Schleife
# schickt und jeder Neustart den offenen Stundenpuffer kostet (Regel 4).
# Aufruf ueber sh, damit das Skript kein Exec-Bit aus dem Git-Checkout braucht
# (Windows-Arbeitskopie).
HEALTHCHECK --interval=60s --timeout=10s --start-period=120s --retries=3 CMD ["/bin/sh", "/app/deploy/healthcheck.sh"]

ENTRYPOINT ["./collector"]

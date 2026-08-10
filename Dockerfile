# Multi-stage build: compile with the full Go toolchain, ship only the
# static binary (Bahnpuls_Betrieb_und_Deployment, ADR-002/ADR-009).
FROM golang:1.26-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/collector ./cmd/collector

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
COPY config ./config

# Raw data and the heartbeat file must live on the Coolify Persistent
# Volume, never in the container filesystem (CLAUDE.md Regel 2) — mount it
# at /data and point the collector there via environment variables:
#   BAHNPULS_DATA_DIR=/data/raw
#   BAHNPULS_HEARTBEAT_PATH=/data/heartbeat.json
# See deploy/README.md.
ENTRYPOINT ["./collector"]

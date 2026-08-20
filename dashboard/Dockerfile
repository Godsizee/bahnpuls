# Baut die Evidence-Seite auf dem Server statt in einer fremden CI (ADR-012). Der Grund
# ist nicht Bequemlichkeit: die Rohdaten liegen auf dem Persistent Volume, nicht im Repo
# und nicht auf dem Entwicklungsrechner -- ein Build anderswo koennte nur Fixtures zeigen.
#
# Der Build laeuft deshalb zur Laufzeit (siehe deploy/dashboard-entrypoint.sh), nicht hier:
# waehrend `docker build` ist das Volume nicht gemountet.

FROM node:22-bookworm-slim AS webdeps
WORKDIR /app/dashboard
COPY dashboard/package.json dashboard/package-lock.json ./
RUN npm ci --no-audit --no-fund

FROM node:22-bookworm-slim
# python3 fuer dbt, ca-certificates fuer den Paketzug beim Build
RUN apt-get update  && apt-get install -y --no-install-recommends python3 python3-venv ca-certificates  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN python3 -m venv /opt/venv  && /opt/venv/bin/pip install --no-cache-dir dbt-core==1.12.0 dbt-duckdb==1.11.0

COPY transform ./transform
COPY dashboard ./dashboard
COPY deploy/dashboard-entrypoint.sh deploy/dashboard-rebuild.sh ./deploy/
COPY --from=webdeps /app/dashboard/node_modules ./dashboard/node_modules

# dbt-Pakete beim Bauen holen, nicht beim Start -- sonst braucht der Container Netz zu
# einem Zeitpunkt, an dem er nur ausliefern soll.
RUN cd /app/transform && /opt/venv/bin/dbt deps

# Verzeichnis fuer die DuckDB-Datei; sie ist ein Build-Artefakt im Container-Dateisystem
# und hat auf dem Volume nichts zu suchen.
RUN mkdir -p /app/data

# Als node laufen, nicht als root. Das ist hier kein Ritual, sondern der einzige
# wirksame Schreibschutz auf die Rohdaten: Coolify kann ein fremdes Named Volume weder
# read-only einhaengen noch ueberhaupt teilen (es praefixt jeden Storage-Namen mit der
# App-UUID), also haengt /data als Bind-Mount auf das Volume-Verzeichnis. Dessen Dateien
# gehoeren root, weil der Collector als root schreibt -- ein Prozess als node kann sie
# lesen und nicht anfassen. Damit gilt CLAUDE.md Regel 1 durch Dateirechte statt durch
# Absicht.
RUN chown -R node:node /app
USER node

EXPOSE 3000
ENTRYPOINT ["/bin/sh", "/app/deploy/dashboard-entrypoint.sh"]

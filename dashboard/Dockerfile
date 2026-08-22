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

# Reihenfolge nach Aenderungshaeufigkeit, damit der Layer-Cache etwas taugt: erst die
# Paketdefinition, dann der Paketzug, erst danach der Projektinhalt. Stuenden die COPYs
# davor, wuerfe jede geaenderte Modelldatei auch `dbt deps` weg.
COPY transform/packages.yml transform/dbt_project.yml transform/profiles.yml ./transform/
RUN cd /app/transform && /opt/venv/bin/dbt deps

# --chown statt eines spaeteren `chown -R /app`: das lief ueber node_modules mit rund
# 900 Paketen und kostete bei jedem Bau ueber hunderttausend Dateioperationen.
COPY --chown=node:node --from=webdeps /app/dashboard/node_modules ./dashboard/node_modules
COPY --chown=node:node transform ./transform
COPY --chown=node:node dashboard ./dashboard
COPY --chown=node:node deploy/dashboard-entrypoint.sh deploy/dashboard-rebuild.sh deploy/dashboard-quellen-pruefen.js deploy/dashboard-seitenabfragen-pruefen.py deploy/diagnose.py ./deploy/

# Verzeichnis fuer die DuckDB-Datei; sie ist ein Build-Artefakt im Container-Dateisystem
# und hat auf dem Volume nichts zu suchen.
RUN mkdir -p /app/data && chown -R node:node /app/data /app/transform

# Als node laufen, nicht als root. Das ist hier kein Ritual, sondern der einzige
# wirksame Schreibschutz auf die Rohdaten: Coolify kann ein fremdes Named Volume weder
# read-only einhaengen noch ueberhaupt teilen (es praefixt jeden Storage-Namen mit der
# App-UUID), also haengt /data als Bind-Mount auf das Volume-Verzeichnis. Dessen Dateien
# gehoeren root, weil der Collector als root schreibt -- ein Prozess als node kann sie
# lesen und nicht anfassen. Damit gilt CLAUDE.md Regel 1 durch Dateirechte statt durch
# Absicht.
USER node

# Ohne Healthcheck schaltet Coolify den Verkehr sofort auf den neuen Container um -- der
# baut beim Start aber erst dbt und Evidence, und bis dahin lauscht nichts auf 3000.
# Ergebnis war ein mehrminuetiges 502-Fenster bei jedem Deploy.
#
# **start-period knapp halten.** Coolify wartet die Startphase **vollstaendig ab**, bevor
# es ueberhaupt zu pruefen beginnt ("Waiting for the start period before starting
# healthcheck") -- anders als Docker, wo ein erfolgreicher Check darin sofort zaehlt. Der
# Wert ist damit keine Reserve, sondern aufgeschlagene Deploy-Zeit: mit 900 s stand ein
# laengst gesunder Container 15 Minuten lang als "in progress".
#
# Gemessen dauert der Start 83 s (dbt 18 s, Quellen 6 s, Seitenbau 59 s). 150 s plus
# 5 Versuche im 15-s-Takt geben knapp das Dreifache als Toleranz.
#
# Kein curl im Image, also prueft node selbst.
HEALTHCHECK --interval=15s --timeout=5s --start-period=150s --retries=5 CMD ["node", "-e", "require('http').get('http://127.0.0.1:3000/', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"]

EXPOSE 3000
ENTRYPOINT ["/bin/sh", "/app/deploy/dashboard-entrypoint.sh"]

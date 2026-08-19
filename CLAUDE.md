# Bahnpuls — Projektregeln

Verspätungs-Analytics für den Schienenverkehr (VRN + RMV). Datenpipeline- und
Analyseprojekt — **kein CRUD, kein PWA, kein n8n** (ADR-001, ADR-006). Vollständiger
fachlicher und architektonischer Kontext liegt im Vault, nicht in diesem Repo:

```
C:\Users\bades\OneDrive\Desktop\Ideen\02 Projekte\Bahnpuls\
```

## Pflichtlektüre zu Sessionbeginn

1. Diese Datei
2. `_ai/project-context.md` und `Recent.md` im Vault
3. `Backlog.md` (Abschnitt NOW) für die aktuell anstehende Aufgabe
4. die zur Aufgabe passende Datei aus `Referenz/Bahnpuls_*.md` — bei Fragen zu
   Datenfeldern, Kennzahlen oder Fallstricken dort nachschlagen, **nicht aus dem
   Gedächtnis beantworten**

## Nicht verhandelbare Regeln

Diese Punkte kosten bei Verletzung entweder unwiederbringliche Historie oder verfälschen
jede nachgelagerte Kennzahl. Sie sind nicht durch Zeitdruck oder Bequemlichkeit
aufhebbar.

1. **Rohdaten sind unveränderlich.** Nie überschreiben, nie in-place korrigieren, nie
   „aufräumen". Jede Korrektur passiert ausschließlich in der Transformationsschicht
   (dbt). GTFS-RT hat kein Archiv — eine verworfene oder überschriebene Zeile ist für
   immer weg.
2. **Rohdaten liegen ausschließlich auf dem Persistent Volume, nie im
   Container-Dateisystem.** Ein Coolify-Redeploy löscht das Container-FS restlos. Vor dem
   ersten produktiven Deploy ist ein Redeploy-Test mit Datenkontrolle Pflicht
   (BPULS-020) — dieser Test darf nicht übersprungen werden.
3. **Der Collector hat Vorrang.** Bei Konflikten zwischen Collector-Stabilität und allem
   anderen (Analyse, Dashboard, Refactoring) gewinnt der Collector. Ein Tag ohne
   laufenden Collector ist endgültig verlorene Historie.
4. **Sauberes Shutdown ist Pflicht.** `SIGTERM` muss den offenen Stundenpuffer vor
   Prozessende auf das Volume flushen. Ohne das kostet jedes Deployment bis zu einer
   Stunde Daten.
5. **Zeitzonendatenbank fest im Binary/Image.** Bevorzugt `import _ "time/tzdata"` im
   Go-Code, alternativ `tzdata` im Docker-Image. `Europe/Berlin` darf nie erst zur
   Laufzeit unauflösbar sein.
6. **Betriebstag ≠ Kalendertag.** GTFS-Zeiten wie `25:30:00` sind Sekunden seit
   Betriebstagsbeginn. Niemals als Uhrzeit parsen (`CAST … AS TIME` ist hier ein Bug,
   kein Sonderfall) — das verliert genau die Nachtfahrten mit den interessantesten
   Störungen.
7. **Scope-Filter läuft über eine Haltestellenliste, nie über Verbund/Agency.** VRN/RMV
   sind Tarifverbünde, keine Datenkategorie — ein Agency-Filter würde den Fernverkehr
   fälschlich ausschließen. Die Liste ist Konfiguration, nicht einkompiliert (ADR-008).
8. **Ausfall ≠ Verspätung 0.** `zug_ausgefallen`/`halt_ausgelassen` nie in
   Pünktlichkeitsdurchschnitte einrechnen, aber immer danebenstellen.
9. **Ist-Daten werden gegen die zum Ereigniszeitpunkt gültige Static-Version gejoint**,
   nie gegen die aktuelle. Static bleibt versioniert unter `static/v=YYYY-MM-DD/`.
10. **Marts werden ab M1 inkrementell materialisiert** (`materialized='incremental'`),
    kein nächtlicher Vollaufbau.
11. **Das Dashboard fragt ausschließlich `marts` ab**, nie Fakten- oder Rohdaten direkt.
12. **Keine personenbezogenen Daten, kein Tracking.** Verarbeitet werden ausschließlich
    Fahrplan- und Betriebsdaten.
13. **Tonalität sachlich, nie anklagend.** Befunde werden als Zahl formuliert, nicht als
    Vorwurf — Beispiele in `Referenz/Bahnpuls_Recht_und_Lizenz.md`. Das Projekt wird in
    Bewerbungen bei EVU/Verkehrsverbünden verlinkt.
14. **Keine Secrets im Repo**, ab Tag 1, auch wenn aktuell keine gebraucht werden.
    Secrets gehören in Coolify Environment Variables. Das Repo muss **jederzeit
    öffentlich auf GitHub einsehbar sein können**, ohne sensible Daten preiszugeben —
    `.gitignore` deshalb **immer aktuell halten**: bei jeder neu hinzukommenden
    Datei-Art (Env-Dateien, lokale Configs, Dumps, Credentials, IDE-/Editor-Settings)
    sofort ergänzen, nicht nachträglich. Vor jedem Commit/Push prüfen, ob etwas
    Sensibles versehentlich mitgeht (`git status`, Inhalt neuer Dateien ansehen).
15. **Scope ist VRN + RMV** (ADR-008, ADR-010). Gesammelt wird ausschließlich dieses
    Gebiet — die bundesweite Sammelvariante ist gestrichen, Q12 ist seit 2026-08-19
    entschieden. „VRN" ist der **Verkehrsverbund Rhein-Neckar**, nicht die
    Rhein-Neckar-Verkehr GmbH (RNV); RNV ist ein Unternehmen im Gebiet, kein Gebiet.
    Keine eigenmächtige Ausweitung, auch nicht „nur zum Messen".

## Architektur-Leitplanken

Go (Collector) · Parquet + ZSTD · DuckDB · dbt-duckdb · Evidence.dev · Docker/Coolify ·
Cloudflare Pages (Dashboard).

**Bewusst nicht im Stack:** n8n, PocketBase/Supabase, Svelte/Next, PWA/Service-Worker,
Kubernetes, Kafka/Airflow (ADR-001, ADR-006; siehe `Decisions.md`). Legt eine Aufgabe
eines dieser Werkzeuge nahe: erst die Architekturentscheidung in `Decisions.md` prüfen,
nicht stillschweigend einführen.

**Zuständigkeiten strikt getrennt (SRP):** Collector sammelt, dbt transformiert, Evidence
zeigt. Keine Analyse-Logik im Collector, keine Datenbeschaffung in dbt.

## Coding-Prinzipien

### Allgemein

- KISS: ein Container mit einem Binary, Dateien auf einem Volume, eine embedded DB, eine
  statische Site. Kein Message Broker, kein Orchestrator für einen Feed.
- YAGNI: keine Abstraktion für eine hypothetische zweite Quelle, bevor sie ansteht.
  Ausnahme: die in ADR-007 bereits eingeplante Quellen-Normalisierung im Staging-Layer,
  die ist kein „Vorrat", sondern trägt bereits die Zwei-Spuren-Strategie.
- OCP: neue Quelle = neues Staging-Modell auf dem `fct_stop_events`-Schema.
  Intermediate/Marts bleiben unangetastet.
- Kommentare nur für WHY (nicht-offensichtliche Invarianten wie Betriebstag-Handling,
  bewusste Workarounds), nie WHAT — der Code sagt, was er tut.
- Kleine, benannte Funktionen statt tief verschachtelter Logik, besonders im
  Poll-/Decode-Pfad des Collectors, der monatelang unbeaufsichtigt laufen muss.

### Go (Collector, Static-Loader)

- Go 1.23+, `CGO_ENABLED=0`, statisches Binary.
- Fehler werden über die Aufrufkette gewrappt (`fmt.Errorf("...: %w", err)`), nie
  stillschweigend verschluckt.
- Panic-Recovery ausschließlich im äußeren Poll-Loop — ein Crash darf höchstens den
  aktuellen Stundenpuffer kosten, nicht als genereller Fehlerkanal missbraucht werden.
- `context.Context` für Cancellation; der `SIGTERM`-Handler flusht den Puffer vor Exit.
- Kein globaler mutable State außer dem explizit dokumentierten Dedup-/Puffer-State.
- Table-driven Tests für Decode- und Filterlogik.
- `gofmt` und `go vet` vor jedem Commit sauber; Linter-Setup ergänzen, sobald das Repo
  angelegt ist (BPULS-001).

### SQL / dbt

- Layer-Grenzen einhalten: `staging` (view, reine Normalisierung/Typisierung) →
  `intermediate` (table, Zustandslogik) → `marts` (table/incremental, fertige
  Kennzahlen). Keine Business-Logik in `staging`.
- Jedes neue Modell bekommt passende Tests (`unique`, `not_null`, `accepted_range` — die
  Minimum-Liste in `Referenz/Bahnpuls_Datenmodell.md` ist ab M1 Pflicht, nicht optional).
- Lesbare, benannte CTEs statt verschachtelter Subqueries.
- Kennzahlen, die pro Zug variieren (z. B. Engpassknoten), werden normiert ausgewiesen,
  nie als Rohsumme.

### Evidence.dev / Dashboard

- Seiten fragen ausschließlich `marts` ab, nie Fakten- oder Rohdaten.
- Jede neue oder geänderte Kennzahl wird zeitgleich auf der Methodik-Seite dokumentiert
  (BPULS-015) — nicht nachträglich.

## Workflow-Regeln

- Bestehende Notizen im Vault erweitern statt neue Dateien anlegen. Fachliche
  Definitionen existieren nur einmal, in `Referenz/` — anderswo verlinken, nicht
  wiederholen.
- Tasks ausschließlich in `Backlog.md` (Präfix `BPULS-xxx`), Architekturentscheidungen
  als ADR in `Decisions.md`.
- Nach jeder Session: neuer Eintrag oben (neuester zuerst) in `Recent.md`; `Backlog.md`
  aktualisieren, wenn Aufgaben erledigt oder neu entdeckt wurden.

## Was hier nicht passiert

- Kein n8n, keine CRUD-Web-App, kein PWA/Service-Worker (ADR-001, ADR-006).
- Keine Kubernetes-/Kafka-/Airflow-Einführung „auf Vorrat".
- Kein Zurückgreifen auf bestehende Bausteine aus FairShare/Life OS — bewusste
  Entscheidung, siehe ADR-001.
- Keine eigenmächtige Scope-Erweiterung über VRN + RMV hinaus (ADR-010).

## Referenzen im Vault

| Datei | Wofür |
|---|---|
| `Referenz/Bahnpuls_Konzept.md` | Problem, Zielbild, Scope, Abgrenzung |
| `Referenz/Bahnpuls_Datenquellen.md` | GTFS-RT-Felder, CH-Ist-Daten, Volumen, Lizenzen |
| `Referenz/Bahnpuls_Architektur.md` | Stack, Datenfluss, Repo-Struktur |
| `Referenz/Bahnpuls_Datenmodell.md` | dbt-Layer, Tabellen, **Fallstricke** |
| `Referenz/Bahnpuls_Analysen.md` | A1–A7, die fachlichen Auswertungen |
| `Referenz/Bahnpuls_Roadmap.md` | Meilensteine, Zeitrahmen |
| `Referenz/Bahnpuls_Betrieb_und_Deployment.md` | Coolify, Volumes, Monitoring, Retention |
| `Referenz/Bahnpuls_Recht_und_Lizenz.md` | Attribution, Tonalität |
| `Decisions.md` | ADR-001 bis ADR-009 — Begründungen hinter den Regeln oben |

---

# TOKEN SAVING DIRECTIVES

## 1. General Principles
* **Zero Fluff:** Omit all greetings, polite intro/outro phrases ("Sure!", "Here is...", "Hope this helps!").
* **No Echoing:** Never restate or summarize the user's prompt or problem.
* **Direct Answers Only:** Jump straight to the code, solution, or answer.

## 2. Code Output & Diffs
* **Targeted Changes:** Never rewrite full files unless explicitly requested or creating a new file.
* **Use Placeholders:** Use standard line comments for unchanged code (e.g., `// ... existing code ...` or `# ... existing setup ...`).
* **Minimal Scope:** Output only the modified functions, lines, or blocks with just enough context to place them correctly.

## 3. Explanations & Reasoning
* **Code First:** Do not explain code unless explicitly asked to do so ("explain this", "why?", etc.).
* **Ultra-Brief Prose:** If text is necessary, limit it to bullet points and maximum 1–2 short sentences.
* **No CoT Output:** Keep internal step-by-step reasoning concise and silent. Do not output verbose thinking processes.

## 4. Formatting Rules
* Avoid redundant Markdown headers or multi-level wrappers.
* Avoid redundant code comments that duplicate self-explanatory code logic.
* Keep formatting minimal and high-density.

<!-- rtk-instructions v2 -->
# RTK (Rust Token Killer) - Token-Optimized Commands

## Golden Rule

**Always prefix commands with `rtk`**. If RTK has a dedicated filter, it uses it. If not, it passes through unchanged. This means RTK is always safe to use.

**Important**: Even in command chains with `&&`, use `rtk`:
```bash
# ❌ Wrong
git add . && git commit -m "msg" && git push

# ✅ Correct
rtk git add . && rtk git commit -m "msg" && rtk git push
```

## RTK Commands by Workflow

### Build & Compile (80-90% savings)
```bash
rtk cargo build         # Cargo build output
rtk cargo check         # Cargo check output
rtk cargo clippy        # Clippy warnings grouped by file (80%)
rtk tsc                 # TypeScript errors grouped by file/code (83%)
rtk lint                # ESLint/Biome violations grouped (84%)
rtk prettier --check    # Files needing format only (70%)
rtk next build          # Next.js build with route metrics (87%)
```

### Test (60-99% savings)
```bash
rtk cargo test          # Cargo test failures only (90%)
rtk go test             # Go test failures only (90%)
rtk jest                # Jest failures only (99.5%)
rtk vitest              # Vitest failures only (99.5%)
rtk playwright test     # Playwright failures only (94%)
rtk pytest              # Python test failures only (90%)
rtk rake test           # Ruby test failures only (90%)
rtk rspec               # RSpec test failures only (60%)
rtk test <cmd>          # Generic test wrapper - failures only
```

### Git (59-80% savings)
```bash
rtk git status          # Compact status
rtk git log             # Compact log (works with all git flags)
rtk git diff            # Compact diff (80%)
rtk git show            # Compact show (80%)
rtk git add             # Ultra-compact confirmations (59%)
rtk git commit          # Ultra-compact confirmations (59%)
rtk git push            # Ultra-compact confirmations
rtk git pull            # Ultra-compact confirmations
rtk git branch          # Compact branch list
rtk git fetch           # Compact fetch
rtk git stash           # Compact stash
rtk git worktree        # Compact worktree
```

Note: Git passthrough works for ALL subcommands, even those not explicitly listed.

### GitHub (26-87% savings)
```bash
rtk gh pr view <num>    # Compact PR view (87%)
rtk gh pr checks        # Compact PR checks (79%)
rtk gh run list         # Compact workflow runs (82%)
rtk gh issue list       # Compact issue list (80%)
rtk gh api              # Compact API responses (26%)
```

### JavaScript/TypeScript Tooling (70-90% savings)
```bash
rtk pnpm list           # Compact dependency tree (70%)
rtk pnpm outdated       # Compact outdated packages (80%)
rtk pnpm install        # Compact install output (90%)
rtk npm run <script>    # Compact npm script output
rtk npx <cmd>           # Compact npx command output
rtk prisma              # Prisma without ASCII art (88%)
```

### Files & Search (60-75% savings)
```bash
rtk ls <path>           # Tree format, compact (65%)
rtk read <file>         # Code reading with filtering (60%)
rtk grep <pattern>      # Search grouped by file (75%). Format flags (-c, -l, -L, -o, -Z) run raw.
rtk find <pattern>      # Find grouped by directory (70%)
```

### Analysis & Debug (70-90% savings)
```bash
rtk err <cmd>           # Filter errors only from any command
rtk log <file>          # Deduplicated logs with counts
rtk json <file>         # JSON structure without values
rtk deps                # Dependency overview
rtk env                 # Environment variables compact
rtk summary <cmd>       # Smart summary of command output
rtk diff                # Ultra-compact diffs
```

### Infrastructure (85% savings)
```bash
rtk docker ps           # Compact container list
rtk docker images       # Compact image list
rtk docker logs <c>     # Deduplicated logs
rtk kubectl get         # Compact resource list
rtk kubectl logs        # Deduplicated pod logs
```

### Network (65-70% savings)
```bash
rtk curl <url>          # Compact HTTP responses (70%)
rtk wget <url>          # Compact download output (65%)
```

### Meta Commands
```bash
rtk gain                # View token savings statistics
rtk gain --history      # View command history with savings
rtk discover            # Analyze Claude Code sessions for missed RTK usage
rtk proxy <cmd>         # Run command without filtering (for debugging)
rtk init                # Add RTK instructions to CLAUDE.md
rtk init --global       # Add RTK to ~/.claude/CLAUDE.md
```

## Token Savings Overview

| Category | Commands | Typical Savings |
|----------|----------|-----------------|
| Tests | vitest, playwright, cargo test | 90-99% |
| Build | next, tsc, lint, prettier | 70-87% |
| Git | status, log, diff, add, commit | 59-80% |
| GitHub | gh pr, gh run, gh issue | 26-87% |
| Package Managers | pnpm, npm, npx | 70-90% |
| Files | ls, read, grep, find | 60-75% |
| Infrastructure | docker, kubectl | 85% |
| Network | curl, wget | 65-70% |

Overall average: **60-90% token reduction** on common development operations.
<!-- /rtk-instructions -->

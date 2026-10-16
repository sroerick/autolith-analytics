# autolith-analytics

Fleet analytics: what the machine spent, where it went.

One small process. Own heap, own build, disposable. Truth lives in the
event files, never in the process.

## Shape

```
autolith runtime (SBCL)  --append-->  events/autolith.jsonl
pp-flow adapter          --append-->  events/pp-flow.jsonl
saguaro bridge           --append-->  events/bridge.jsonl
                              |
   analytics process (this repo; wg0 only)
   reads + rolls up + serves JSON + one HTML pane
                              |
   autolith-webui links to it. Nothing imports anything.
```

- Producers are dumb: one append per event, best-effort. A failed append
  never blocks or signals the producer.
- This repo owns the schema, the rollups, and the pane. It never rewrites
  producer files.
- The webui gets a link, not a dependency. Analytics can rebuild or
  restart freely; the console doesn't notice.

## Layout

- `docs/schema-v1.md` - the event contract (read this first)
- `events/` - local event files (gitignored)
- `src/` - ASDF system `:autolith-analytics` (to be built)
- `Makefile` - build/run/smoke, mirroring autolith-webui's

## Rules

1. Counts and ids only. No transcripts, no prompt text, no completions,
   no credentials. This keeps the repo publishable and the ledger clean.
2. Append-only. The reader tails; nothing rewrites event files.
3. Schema evolution: adding optional fields is free; renaming or removing
   a field is a v2.
4. Binds wg0 only. Nothing public until roerick says so.

## Producers (M1/M3/M4)

All producers append best-effort and never block or signal on failure.
Default target is `~/dev/wyo.tech/autolith-analytics/events/`; pp-flow and
the bridge override the directory with `ANALYTICS_EVENTS_DIR`, the runtime
hook the exact file with `ANALYTICS_EVENTS_FILE`. Actor is `$USER` unless
`ANALYTICS_ACTOR` is set.

| producer | lives in | writes |
|---|---|---|
| M1 runtime hook | autolith `src/provider/client.lisp` (`provider-stream-turn :around`) | `events/autolith.jsonl` |
| M3 pp-flow adapter | pricklypear `scripts/pp-flow-autolith.sh` | `events/pp-flow.jsonl` |
| M4 bridge | picoclaw-bridge `main.go` (`sendChat`/`handleChat`) | `events/bridge.jsonl` |

## Run

```
make build          # dumps bin/autolith-analytics
make smoke          # reader + rollup self-test against the schema examples
./bin/autolith-analytics [--port 8787] [--address wg0]
```

Binds wg0 by default; loopback is the dev fallback when wg0 is absent.
The reader tails `events/` - nothing else writes there.

## Milestones

- M1 autolith exporter hook: ~20 lines in the runtime's provider-call
  path; one `llm-usage` line per completed call, best-effort.
- M2 reader + rollups + pane: spend per day / per model / per actor.
- M3 pp-flow producer: the adapter already parses `:INPUT-TOKENS/`
  `:OUTPUT-TOKENS/:PROVIDER-REQUESTS` and drops them - stop dropping.
- M4 bridge producer: message volume per actor per day.

## Working arrangement

Built by roerick's agent; gregor reviews schema changes and diffs.
Local dev on vultr.guest; an rc.d entry only when it leaves dev.

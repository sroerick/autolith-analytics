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

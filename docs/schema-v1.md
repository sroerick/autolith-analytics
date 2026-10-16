# Event schema v1

## Files

JSONL: one UTF-8 JSON object per line, newline-terminated.

Path: `events/<source>.jsonl` (e.g. `events/autolith.jsonl`). Date-suffixed
rotation (`events/<source>-YYYYMMDD.jsonl`) is optional later; the reader
must handle both patterns, each producer picks one and stays with it.

## Fields

| field | type | req | notes |
|---|---|---|---|
| ts | string, ISO-8601 UTC | yes | e.g. 2026-10-16T18:27:00Z |
| schema_v | integer | yes | 1 |
| source | string | yes | autolith, pp-flow, bridge, ... |
| kind | string | yes | llm-usage, run-step, message (additions allowed) |
| actor | string | yes | who acted: gregor, roerick, runner id |
| model | string | no | provider model id (llm-usage) |
| tokens_in | integer | no | provider-reported input tokens |
| tokens_out | integer | no | |
| cached_tokens | integer | no | a count, not a percent |
| requests | integer | no | provider requests (llm-usage: 1) |
| wall_s | number | no | seconds |
| run_id | string | no | orchestrator run / pp-flow pass id |
| ref | string | no | short pointer, ids only: job:exec:42, card:f7c4579b |
| dir | string | no | in / out; kind=message only |
| note | string | no | max 200 chars; never free-form transcript |

Unknown fields may appear; readers ignore them. New kinds display as
"other" until the reader learns them.

## Kinds in v1

- `llm-usage` - one provider call completed.
- `run-step` - an executor step boundary (usage fields optional).
- `message` - bridge message volume.

## Hygiene

Never in an event: transcripts, prompt text, completions, credentials,
auth tokens. Counts, ids, durations, model names only. Enforced by review;
the reader may also refuse lines carrying more than ~200 chars of free
text outside `note`.

The usage on a run-step is the executor's self-report (parsed from
terminal summaries today). Treat it as advisory until provider-structured
usage lands; the budget story is documented in the orchestrator recon
(docs/handoffs/, D4 Q4).

## Examples

```
{"ts":"2026-10-16T18:27:00Z","schema_v":1,"source":"autolith","kind":"llm-usage","actor":"gregor","model":"gpt-5","tokens_in":41233,"tokens_out":812,"cached_tokens":36000,"requests":1,"wall_s":6.4,"ref":"job:exec:42"}
{"ts":"2026-10-16T18:29:12Z","schema_v":1,"source":"pp-flow","kind":"run-step","actor":"hollis","run_id":"pp-pass-2026-10-16","requests":3,"tokens_in":1750000,"tokens_out":21000,"cached_tokens":1550000,"wall_s":120.5}
{"ts":"2026-10-16T18:30:00Z","schema_v":1,"source":"bridge","kind":"message","actor":"roerick","dir":"in"}
```

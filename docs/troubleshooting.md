# Troubleshooting

## An issue number disappears in the shell

In an interactive shell, an unquoted `#26` starts a comment, so the shell does not pass it to the
command. Dispatch CLI arguments use the bare number:

```sh
dispatch status 26
```

If another command accepts the `#26` form, quote it as `'#26'` so the shell passes it literally.

## Worktree commits fail under a sandbox

A linked worktree stores its Git metadata in the main repository's common `.git` directory, outside
the worktree. A workspace-write sandbox therefore needs write access to that directory or commits
can fail while creating `index.lock`.

Dispatch already resolves the absolute Git common directory and passes
`--add-dir <git-common-dir>` to Codex, Claude, and Kimi workers. Do not add another workaround to a
generated worker command unless that behavior has changed.

## `model alias '<name>' not found`

The name is neither present in `models.conf` nor a raw slug whose provider dispatch can infer. Add or
correct an entry using this format, then check it with `dispatch models`:

```conf
alias = provider exact-model-string
```

`DISPATCH_MODELS_CONF` can point dispatch at a different file. If it is set, fix that file rather
than the default file beside `bin/dispatch`.

Kimi model IDs are provider-prefixed. For example, use `moonshot-ai/kimi-k3`, not bare `kimi-k3`;
the ID must also match the Kimi Code configuration.

## A deployed change is not visible

`dispatch` does not deploy sites or purge caches. `[VERIFY]` A post-deploy CDN or GridPane cache may
continue serving the previous version; confirm the deployed revision and inspect or purge the
relevant cache outside dispatch.

## `dispatch gate` refuses a job

The gate only accepts a job whose current state is `DONE`. Wait for a running job, inspect a failed
job with `dispatch logs <n>`, or start over with `dispatch clean <n>` followed by `dispatch start`.

## A claude worker finished but the foreman got no report

Reporting is best-effort and most of its failure modes are silent by design, so absence of a report
never means the job failed — check `dispatch status <n>` first; the exit code on disk is the truth.

Then work through the reasons a report legitimately does not arrive, in likelihood order:

1. **The job was silent to begin with.** `dispatch start` printed `reporting: off` if the worker was
   codex/gemini/kimi, `--no-report` was passed, or the foreman had no addressable name at start
   time. `grep report= .dispatch/jobs/<n>/meta` shows what the job recorded.
2. **The foreman runs in `bypassPermissions`.** Reports are held rather than delivered — measured
   never to arrive at a non-interactive foreman — while the worker still sees its send succeed. Use
   a prompting mode (see [modes.md](modes.md)).
3. **Messaging is disabled by an env var.** `DISABLE_TELEMETRY`, `DO_NOT_TRACK`,
   `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, or `DISABLE_GROWTHBOOK` each turn it off with no
   visible signal. `dispatch doctor` names the offender.
4. **The foreman session exited (or its name was recycled) between `start` and the worker
   finishing.** The send fails or lands elsewhere; the worker finishes normally either way. The
   name the worker targeted is in `foreman=` in the job's `meta`.
5. **The worker gave up on the send.** Its transcript is in `.dispatch/jobs/<n>/events.jsonl` —
   look for the SendMessage tool call near the end; a refusal quoting a `[ref]` followed by no
   retry means the worker did not follow the retry instruction.

If a *running* worker also cannot be reached for steering, remember its socket disappears at exit —
"already gone" is a normal outcome, not a fault. Fall back to `dispatch rework` or stop/re-start.

## `dispatch logs <n> --events` prints a wall of identical `started` lines

`render_event`'s `claude`/`deepseek` branch ends in this line (`bin/dispatch:202`):

```sh
elif .type=="system" then "started" else .type end'
```

It collapses *every* `system` record to the literal string `started`. That was written against
claude's stream, where the only `system` record observed is `init` (see
[claude-events.md](claude-events.md)), so the line reads as "the run started".

A deepseek worker emits one `system`/`thinking_tokens` record per thinking-token chunk — 19,055 of
them in the captured run (see [deepseek-events.md](deepseek-events.md)). `dispatch logs <n> --events`
renders a 40-line window over the stream (`bin/dispatch:716`, `tail -40 "$events" | while … render_event`),
and for a deepseek job that window is all `thinking_tokens`. Every line renders as the same word, so
the output shows no tool names and no message text — 34 consecutive `started` lines in the capture.

**Read a channel that isn't the event window:**

- `dispatch logs <n>` (no flag) tails `worker.log` — the CLI's stderr, its human progress stream.
- `dispatch logs <n> --raw` shows that same file verbatim.
- `dispatch logs <n> -f --events` still fills with `started`; it is the event stream, not the worker.

## `dispatch wait` shows the final message as a fragment

`dispatch wait` prints the worker's final message as a fragment that starts mid-report, even though
the `result` record holds the complete text.

Two lines produce it. `last_message.txt` is written by `bin/dispatch:552`:

```sh
jq -r 'select(.type=="result") | .result // .text // empty' "$jd/events.jsonl" | tail -1 > "$jd/last_message.txt"
```

`jq -r` prints `.result` raw, so a multi-paragraph report comes out as many lines; `tail -1` then
keeps the **last line of that text**, not the last record. Every line above it is discarded. If the
report ends with a newline, the surviving line is empty and `final:` shows nothing at all.

The display side is `bin/dispatch:655`, which folds newlines to spaces and cuts the line at 160
characters:

```sh
ev="final: $(tr '\n' ' ' < "$jd/last_message.txt" | cut -c1-160)"
```

so a long final line is additionally clipped mid-sentence. `cmd_wait` reaches this through
`print_job_row` (`bin/dispatch:785`); `dispatch status <n>` prints the same line via
`bin/dispatch:679`.

The identical `tail -1` pipeline is used for claude (`bin/dispatch:521`) and kimi
(`bin/dispatch:589`). Codex avoids the problem by letting its CLI write the file (`-o`,
`bin/dispatch:493`).

The gate does *not* have this bug — `bin/dispatch:844` slurps the records and takes the last one:

```sh
jq -rs '[.[] | select(.type=="result") | .result // .text // empty] | last // empty'
```

so a gate reviewing the same job sees the full report while `dispatch wait` does not. The gate
prompt's `UNVERIFIED WORKER CLAIM` block is built from the same truncated file (`bin/dispatch:996`).

Read the report as the worker wrote it:

```sh
jq -r 'select(.type=="result") | .result' .dispatch/jobs/<n>/events.jsonl
```

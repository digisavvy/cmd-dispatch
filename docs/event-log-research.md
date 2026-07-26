# Immutable event log for dispatch job state

Research date: 2026-07-26. Research only — no behavior changed by this note.

The premise under evaluation: long-running agent systems should record an immutable, append-only
event log rather than mutable checkpoints, buying full audit, replay, forkable timelines, and the
freedom to change projection strategy later. This note tests that premise against what `dispatch`
actually does today, measures the append-concurrency question instead of repeating folklore, and
checks the cautionary numbers about Codex's logging against issues that were really filed.

The discussion said to have prompted this issue (attributed to Yohei Nakajima and David K. Piano)
was not located, so nothing here rests on it. `[VERIFY]` The argument is evaluated on its merits.

## Current state, verified against `bin/dispatch`

| Store | Mutability | Where |
| --- | --- | --- |
| `.dispatch/ledger.log` | Append-only. Never rewritten or truncated anywhere in the script. | Appended at `bin/dispatch:394` (`start`), `:563` (`stop`), `:650` and `:783` (`gate`), `:892` (`rework`), `:922` (`pr`) |
| Job `meta` | Mutable. `meta_set` rewrites the whole file through `mktemp` + `mv`. | `bin/dispatch:96` |
| `events.jsonl`, `worker.log` | Truncated every round — each generated `run.sh` redirects with `>`. | `bin/dispatch:312`, `:325`, `:339`, `:354` |
| `attempts/<n>/` | Written once per rework round, then untouched. | `bin/dispatch:881` |
| Whole job dir | Deleted outright by `dispatch clean`. | `bin/dispatch:943` (`rm -rf "$jd"`) |

So dispatch already runs a small event-sourced system. `dispatch report` is a pure projection: an
`awk` fold over `ledger.log` with no other input (`bin/dispatch:1159`). The interesting question is
not "should dispatch adopt an event log" — it has one — but **what is missing from the log, and what
is destroyed that should not be.**

Two concrete gaps fall out of the table above:

1. **The ledger has no terminal event.** Verbs are `start`, `stop`, `gate`, `rework`, `pr`. A worker
   that finishes writes `exitcode` into the job dir and never touches the ledger. So in the ledger, a
   job that failed, a job still running, and a job whose worktree was cleaned away are
   indistinguishable — all of them are a `start` line with nothing after it. `dispatch report` can
   only count dispatches and approvals; it structurally cannot report a failure rate.
2. **`clean` is both destructive and invisible.** It removes `gate.md`, every archived rework round,
   `last_message.txt`, and `meta` (`bin/dispatch:943`), and appends nothing. The evidence behind a
   gate verdict is gone, and the ledger does not even record that it happened.

## 1. What immutability actually buys here

| Claimed benefit | Status today | Verdict |
| --- | --- | --- |
| Audit of gate verdicts across rework attempts | **Already works.** Each round appends `gate issue=<n> verdict=<v> alias=<a> gate_model=<g> attempt=<k>` (`:783`) and each retry appends `rework issue=<n> attempt=<k>` (`:892`). The verdict sequence is fully reconstructable. | Real need, already met. No work. |
| Post-mortem of a FAILED job after `clean` | **Broken.** No terminal event exists; `clean` deletes the evidence and logs nothing. | Real need, unmet. **Highest-value fix.** |
| `report` as a pure projection | Already is (`:1159`). | Met. No work. |
| `status` as a pure projection | Deliberately not, and should stay that way. `job_state` (`:106`) reads `exitcode`, then `kill -0 "$pid"`, then `events.jsonl` mtime. A crashed worker never gets to write a "died" event — liveness is only knowable by probing the OS. An event log cannot express "the process vanished." | Speculative, and an active regression. **Skip.** |
| Re-dispatch / "fork" with prior-round context | No demand signal. `dispatch rework` already covers iteration, and it deliberately does *not* stack context: `write_rework_prompt` (`:815`) rebuilds `prompt.txt` from pristine `prompt.base.txt` plus the latest findings only, so round 3 does not see round 2's feedback. Forking would fight that decision, not extend it. | Speculative. **Skip.** |
| Replay / rebuild all state from events | Nothing to replay onto. The real state is a git worktree and a branch — replaying a JSON log does not recreate them, and git already holds that history immutably. | Speculative. **Skip.** |

The honest summary: of six classic event-sourcing benefits, one is a real unmet need, two are already
satisfied by the existing plain-text ledger, and three do not apply to a tool whose durable state is
a git branch.

## 2. Append atomicity under parallel jobs — measured

Concurrent appends are real, not hypothetical: an auto-gate is spawned detached from `run.sh`
(`:370`), so with several jobs in flight, independent processes append to one `ledger.log`.

### What the standard actually says

POSIX gives the offset guarantee but says nothing that closes the question by itself.

`open()`/`write()`, POSIX.1-2017, verbatim:

> If the O_APPEND flag of the file status flags is set, the file offset shall be set to the end of
> the file prior to each write and no intervening file modification operation shall occur between
> changing the file offset and the write operation.

That prevents lost or overwritten data. It does not promise a write is indivisible. The RATIONALE for
`write()` is explicit about the limit, verbatim:

> This volume of POSIX.1-2017 does not specify the behavior of concurrent writes to a regular file
> from multiple threads, except that each write is atomic (see Thread Interactions with Regular File
> Operations). Applications should use some form of concurrency control.

XSH 2.9.7 "Thread Interactions with Regular File Operations" lists `write()` among functions that
"shall be atomic with respect to each other in the effects specified in POSIX.1-2017 when they
operate on regular files or symbolic links," qualified as: "If two threads each call one of these
functions, each call shall either see all of the specified effects of the other call, or none of
them." It is written in terms of *threads*; the Linux `write(2)` man page reads it as covering
processes too ("among the effects that should be atomic across threads (and processes) are updates
of the file offset") and records that Linux did not honor it until 3.14.

**The PIPE_BUF folklore is wrong for this case.** `{PIPE_BUF}` appears in `write()` only under
"Write requests to a pipe or FIFO." It is not a regular-file atomicity bound and is irrelevant to
`ledger.log`. The specification's atomicity unit for a regular file is one `write()` call, with no
stated size limit.

Sources: [`write()`](https://pubs.opengroup.org/onlinepubs/9699919799/functions/write.html) and
[XSH 2.9.7](https://pubs.opengroup.org/onlinepubs/9699919799/functions/V2_chap02.html),
POSIX.1-2017; [`write(2)`](https://man7.org/linux/man-pages/man2/write.2.html), Linux man-pages 6.18.

### What this machine actually does

Measured locally on Darwin 25.3.0 arm64 (APFS), reproducing dispatch's exact pattern — one
`echo … >> file` per event, one process per writer, no locking:

| Test | Result |
| --- | --- |
| 16 writers × 500 lines, ~100 B lines (ledger-sized) | 8000 lines, 8000 well-formed, **0 torn** |
| bash builtin `echo`, lines ≤ ~1024 B | 0 torn |
| bash builtin `echo`, lines ≥ ~1025 B | ~70% torn — fragments interleaved mid-line |
| `/bin/echo` (one `write(2)`), 2 KB lines | 0 torn |
| `/bin/echo`, 64 KB lines | ~99% torn |

The failure at ~1 KB is **bash, not the kernel**: the builtin flushes its output buffer in chunks, so
one `echo` becomes several `write()` calls and only each chunk is atomic. `/bin/echo` issues a single
syscall and stays intact at 2 KB — well past `{PIPE_BUF}` — confirming the atomicity unit is the
syscall, not `{PIPE_BUF}`. At 64 KB even one `write()` gets split.

**Conclusion: no lock is needed, and none should be added.** The longest line dispatch can currently
emit is a `gate` line at roughly 120 bytes — an order of magnitude below the boundary. The rule to
preserve is not "add flock," it is **one line per event, one `echo`, and keep lines short.** Any
future design that puts gate findings, a diff, or a JSON blob on a ledger line would cross ~1 KB and
start losing records silently. That is the real reason not to move the ledger to JSONL carrying
payloads.

Caveats: this holds for a local filesystem. `O_APPEND` is not reliable over NFS, and the measurements
above are macOS/APFS; Linux/ext4 was not tested. `[VERIFY]` for those environments.

## 3. The Codex cautionary tale — corrected

The issue body cites writer stalls, "100MB+ WAL," "4GB unrotated logs," and "~12 parallel sessions."
Checked against issues filed on `openai/codex`. All cited issues were open at the time of search.

**Substantiated:**

- **Lock contention with parallel CLI processes.** [#20213](https://github.com/openai/codex/issues/20213)
  "Multi-terminal codex CLI freezes due to SQLite lock contention with no BUSY retry": "Running
  multiple `codex` CLI instances against the same `$CODEX_HOME` causes TUI freezes… The root cause is
  contention on the shared `state_5.sqlite` and `logs_2.sqlite`, combined with the absence of
  SQLITE_BUSY retry logic." [#31184](https://github.com/openai/codex/issues/31184): "I have many
  agents with the same CODEX_HOME coding in parallel… `(code: 5) database is locked`."
- **Unbounded session JSONL with no retention.** [#24948](https://github.com/openai/codex/issues/24948):
  "My `~/.codex/sessions` directory is now about 91 GB total, with 184 JSONL files over 100 MB and the
  largest observed file around 1.95 GB." [#34061](https://github.com/openai/codex/issues/34061):
  "approximately 755 GiB of JSONL session data," one file at 6.9 GiB, and "No storage warning,
  retention limit, or automatic pruning was observed before the Data volume reached 99–100% capacity."
  [#35458](https://github.com/openai/codex/issues/35458): `~/.codex/sessions` at ~165 GiB, "four
  ~2.6 GiB rollouts in ~28 minutes."
- **Log DB and WAL bloat.** [#27741](https://github.com/openai/codex/issues/27741) measured
  `logs_2.sqlite` at ~4.5 GB with a ~1.08 GB WAL; [#29237](https://github.com/openai/codex/issues/29237)
  reports a SIGTRAP crash past ~200 MB.

**Not substantiated, and worth correcting because it changes the design conclusion:**

- **"~12 parallel sessions" is not in any filed issue.** #20213's reproduction is *two* terminals.
  Contention starts at two concurrent processes, not twelve. Anything that assumes headroom up to a
  dozen workers is assuming safety that was never reported.
- **"100MB+ WAL" conflates two files.** The 100 MB figure belongs to session JSONL files (#24948).
  The largest reported WAL is 1.08 GB (#27741).
- **"4GB unrotated logs" conflates them again.** 4.5 GB is `logs_2.sqlite`, not a rollout JSONL.
  Reported JSONL maxima are 6.9 GiB (#34061), 2.64 GiB (#35458), 1.95 GB (#24948).

The lesson is sharper than the issue framed it. The problem is not volume at high parallelism; it is
**an unbounded per-event store with no retention policy, plus a shared SQLite writer that serializes
independent processes.** Dispatch's `ledger.log` has the opposite shape — bounded, one short line per
lifecycle transition, no shared writer. The file that resembles Codex's rollouts is `events.jsonl`,
the raw provider stream, which is exactly the file `clean` deletes today. Any proposal to *stop*
deleting it inherits Codex's problem verbatim, and must ship a retention policy in the same change.

## 4. Options

| Option | What it buys | Cost | Verdict |
| --- | --- | --- | --- |
| **A. Add `finish` and `clean` verbs to `ledger.log`** | Failure rate and job outcomes survive `clean`; `report` gains real denominators; the ledger stops lying by omission | ~4 lines in `run.sh` templates + `cmd_clean`; no format change | **Adopt** |
| **B. Archive job artifacts on `clean` instead of deleting** | Post-mortems after cleanup; gate evidence outlives the worktree | A new retention policy that did not exist before — see the Codex evidence | **Adopt, narrowly** — text artifacts only, never `events.jsonl` |
| **C. Convert `ledger.log` to structured `ledger.jsonl`** | Typed fields; easier complex queries | Rewrites `cmd_report`'s `awk`; adds a `jq` dependency to reporting; invites long lines that tear past ~1 KB; needs a migration for existing ledgers | **Skip** — pays a real cost for a query capability nobody has asked for. The existing `<ts> <verb> k=v…` format is already extensible: new verbs and new `k=v` fields are both backward compatible (verified below) |
| **D. Derive `meta` from the event log; keep it only as a cache** | Conceptual purity | Every read becomes a fold; `meta` is mostly immutable config written once at `:376`, with three fields ever mutated (`attempt`, `gate_model`, `pr_url`). `meta_set` is already atomic (`mktemp` + `mv`) | **Skip** — cost with no benefit |
| **E. Make `status` a projection** | Purity | Regression: liveness requires `kill -0`; a crashed worker cannot emit its own death event | **Skip** |
| **F. Preserve `events.jsonl` across rework rounds and cleans** | Full provider-stream replay | This is precisely Codex #34061 / #24948. Multi-GB growth, no bound | **Skip** — rework already archives the round to `attempts/<n>/` (`:881`), which is the useful 5% |
| **G. SQLite for job state** | Queries, transactions | Codex #20213 is direct evidence against it for exactly this workload: independent CLI processes on one DB, stalling at two concurrent instances | **Skip** |
| **H. Kafka / event-store infrastructure** | — | A daemon, a schema registry, and a service dependency for a self-contained bash script whose entire state is one directory | **Skip** |
| **I. Locking (`flock`) around ledger appends** | — | Measurably unnecessary at current line sizes (§2); adds a dependency and a deadlock path | **Skip** |

## Recommendation: adopt partially — options A and B only

The immutable-log thesis is right in principle and dispatch already follows it. It does not follow
that dispatch should adopt more event-sourcing machinery. Weighed against AGENTS.md's discipline —
one job per issue, dispatch-owned state, no fabricated surface area — the lean subset is:

1. **Close the ledger's terminal-event gap** (option A). This is the only real unmet need found, and
   it is small.
2. **Stop `clean` from destroying the review record** (option B), with a retention policy written in
   the same change, and with `events.jsonl` explicitly excluded.

Everything else — JSONL conversion, derived `meta`, projected `status`, forking, SQLite, external
infrastructure — is cost without a demonstrated need. The event log dispatch already has is
plain text, greppable, `awk`-projectable, lock-free, and roughly 120 bytes per event. Those are
features, and the Codex evidence above is a direct argument for keeping them.

## Implementation sketch

**A. Terminal and cleanup events.** Two new verbs, same `<ts> <verb> issue=<n> k=v…` grammar:

```text
<ts> finish issue=<n> state=DONE|FAILED exit=<code> attempt=<k>
<ts> clean  issue=<n> branch=<branch> archived=<relative path|none>
```

`finish` is appended by each generated `run.sh` immediately after `echo $worker_ec > exitcode`
(`bin/dispatch:314`, `:328`, `:342`, `:358`) — after the exit code is durable, so a wedged append can
never block the worker, matching the ordering rule already applied to `notify`. `clean` is appended
by `cmd_clean` before `rm -rf` (`:943`). `stop` already covers the kill path; `finish` should not
double-report it.

With `finish` present, `cmd_report` can gain a FAILED column — but that is a separate change and
should not be bundled with emitting the events.

**B. Archive rather than delete.** In `cmd_clean`, before removing the job directory, move the small
text artifacts into `.dispatch/archive/<n>-<utc-ts>/`:

- Keep: `meta`, `gate.md`, `last_message.txt`, `prompt.base.txt`, `attempts/*/gate.md`,
  `attempts/*/last_message.txt`
- Drop: `events.jsonl`, `worker.log`, `attempts/*/events.jsonl`, `attempts/*/worker.log`, `run.sh`,
  `pid`, `exitcode`, `prompt.txt`

The kept set is the review record and is kilobytes. The dropped set is the unbounded provider stream
— the Codex failure mode. Retention: a fixed cap (prune oldest beyond N archived jobs) applied on
each `clean`, so the bound holds without a separate command. `DISPATCH_ARCHIVE=off` should skip
archiving entirely for anyone who wants today's behavior, and `.dispatch/` is already gitignored, so
nothing here reaches a commit.

Both changes preserve the invariant that makes the current design safe: one short line per event, one
`echo`, no locks.

## Migration and compatibility

`dispatch report` keeps working with **no changes and no dual-write.** Its `awk` (`bin/dispatch:1159`)
dispatches on `$2` and ignores every verb other than `start` and `gate`; its `value()` helper scans
fields from position 3 for a `k=` prefix and ignores unknown keys. New verbs and new fields are both
inert to it.

Verified by running the exact `awk` program from `cmd_report` against a synthetic ledger containing
`finish` and `clean` lines alongside the existing five verbs. Output was byte-identical to the same
ledger with the new lines removed:

```text
ALIAS                DISPATCHED   APPROVED  ACCEPT RATE
5.6                           1          1       100.0%
opus                          1          0         0.0%
```

Old ledgers stay readable: they simply contain no `finish` or `clean` lines. Any future consumer of
`finish` must therefore treat its absence as "unknown," not as "did not finish" — the same
compatibility rule `cmd_gate` already applies to a missing `base_sha` (`:632`) and `gate_can_rework`
to a missing `attempt` (`:803`).

No version line and no format change is needed, which is the strongest practical argument for
option C's rejection: the current format already has the extensibility that JSONL was proposed to
provide.

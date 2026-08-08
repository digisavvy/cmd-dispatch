# Foreman modes

The foreman has three named operating modes. Choose based on the issue's complexity and risk
profile. In dealer's choice (the default), the foreman picks for you and explains why.

Whether a worker *reports back* to the foreman is a separate axis that combines freely with all
three — see [reporting and silent workers](#a-second-axis-reporting-and-silent-workers).

## claude-solo

Dispatch a Claude worker; skip the machine gate. The foreman reviews the worktree diff and
decides whether to open a PR.

Best for: exploratory spikes, internal tooling, issues you plan to review closely anyway.

```sh
dispatch start 41 opus
# worker runs in wt-issue-41
# when DONE:
#   dispatch logs 41        ← read the final message
#   cd ../myrepo-wt-issue-41 && git diff main  ← review the diff
#   dispatch pr 41          ← push branch + open PR
```

Gate: none. You are the only gate.

---

## verified

Dispatch a worker from one provider and review it with a gate from a different provider.
A cross-provider reviewer catches more because it has no stake in the original output.
Bounded rework (`--max-attempts 2`) lets one rejection go back to the worker before the job holds.

Best for: user-facing features, API changes, anything that'll be hard to roll back.

```sh
dispatch start 52 5.6 --gate --gate-model opus --max-attempts 2
# worker: codex/5.6-sol
# gate:   claude/opus (different provider — cross-provider review)
# if gate rejects → one automatic rework, then holds on second rejection
```

When the job shows `DONE`, the gate runs in the background. Before assuming no gate ran, check:

```sh
cat .dispatch/jobs/52/gate.md                   # latest attempt
cat .dispatch/jobs/52/attempts/1/gate.md        # archived round 1 (if rework happened)
```

Gate approval opens a PR automatically. You still review the PR before merging.

**Warning:** Never commit into a gated job's worktree until all its attempts are exhausted — a
rework may be running there.

---

## dealer's choice (default)

When the user does not name a mode or model, the foreman assigns worker + gate per issue and
states the pick and reasoning before dispatching. The user keeps veto at PR time.

### Heuristics

| Situation | Worker | Gate | Attempts |
|---|---|---|---|
| Gnarly logic / infra | best-tier (opus / 5.6) | cross-provider | 2 |
| Well-specced, small scope | balanced (sonnet / 5.6-terra) | same or cross | 1 |
| Docs / mechanical | cheap (haiku / mini) | none | 1 |
| Auth, payments, prod config | best-tier | cross-provider | always |

### Example

```text
User: put someone on #60 (the payment-webhook retry bug)

Foreman: I'll use 5.6-sol as the worker and opus as the gate, 2 attempts.
         Reasoning: payment path — best-tier worker, cross-provider gate, bounded rework.

dispatch start 60 5.6 --gate --gate-model opus --max-attempts 2
```

The foreman announces the assignment. If the pick looks wrong, the user says so before the
worker is dispatched.

---

## A second axis: reporting and silent workers

The three modes above all answer *who reviews the work*. This answers a different question —
*how the foreman finds out the job finished* — so it is **not** a fourth mode. Every combination is
valid: `verified` with a reporting worker, `claude-solo` with a silent one.

- A **reporting** worker messages the foreman's Claude Code session when it finishes.
- A **silent** worker does not. The foreman learns the job ended from `dispatch status`,
  `dispatch wait`, the terminal bell, or the banner.

| Provider | Worker |
|---|---|
| `claude` | **reporting** when the foreman is addressable — opt out with `--no-report` |
| `codex` | silent |
| `gemini` | silent |
| `kimi` | silent |

Only `claude` workers bind an inbox, so reporting is Claude-only by construction. That is not a
regression for the others: they behave exactly as they always have, and the
bell / banner / `DISPATCH_NOTIFY_CMD` path is unchanged for **every** provider, `claude` included.
Reporting is added alongside it, never instead of it.

`dispatch start` prints which one you got:

```text
reporting: on  — this worker will message foreman session 'my-repo-a3' when it finishes
reporting: off — silent worker; use dispatch status/wait, bell, or banner
```

### Run the foreman in a prompting mode

**A foreman in `bypassPermissions` holds the report rather than delivering it.** Measured on macOS
with Claude Code 2.1.226, against a **non-interactive** `bypassPermissions` foreman: the worker's
send returned `{"success":true, "msg_id":…}` and the message never arrived. There is no error on
either side — it simply does not show up. Run the foreman in a prompting mode instead; the `default`
mode is verified to receive the report and surface it mid-session, and `acceptEdits`, `dontAsk`, and
`auto` are the same delivery class per the documented rules.

`[VERIFY]` The scope of that measurement is exactly one configuration. The probe's receiver was
headless and so could never display an approval dialog, which is why nothing arrived. An
*interactive* `bypassPermissions` foreman is expected to be offered a dialog it can answer before
`dialogExpiry` (default five minutes), after which the message is dropped — that path is **untested
here**, so do not read the measurement above as "a `bypassPermissions` foreman can never receive
anything". The recommendation is the same either way: use a prompting mode and the question never
arises.

### What reporting requires

A worker reports only when all of these hold. Otherwise it is silent, and `dispatch start` says so:

- the provider is `claude`, and `--no-report` was not passed;
- the foreman session has a messaging inbox, so `dispatch` can resolve its name;
- Claude Code is v2.1.224 or newer, on macOS or Linux (not native Windows);
- none of `DISABLE_TELEMETRY`, `DO_NOT_TRACK`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, or
  `DISABLE_GROWTHBOOK` is set — any one of them turns messaging off with no visible signal.

`dispatch doctor` checks each of these and names the reason when reporting is unavailable.

The foreman must be **local**. A containerised foreman — Claude Code on the web — cannot reach a
worker on your machine, and cross-machine peers are reply-only.

The foreman's name is resolved once, at `dispatch start`, and recorded in the job's `meta`.
`dispatch rework` rebuilds the prompt from that same record, so a reworked worker reports to the
foreman that started the job — not to whichever session ran the rework. If that original session has
since exited, the send fails harmlessly, the worker finishes normally, and the bell/banner still
fire. Only the headless gate is unaffected either way: it is not a worker and reports through
`dispatch notify` as it always has.

### Names are reusable, so reports can be misaddressed

Two consequences of names being derived from a directory and scoped to the machine. Neither can
leak outside your own user account, and neither affects job state — but both can misdirect a
*message*, so they are worth knowing before you trust one:

- **A recycled foreman name.** Session names come from the working directory, so a session started
  later in the same directory can hold the name a finished foreman used. A rework whose original
  foreman has exited may therefore report into an unrelated newer session rather than failing. The
  report is one status line, and on-disk state remains the source of truth.
- **Worker names are not repo-qualified.** A worker is named `dispatch-issue-<n>`, which is global to
  the machine, so dispatching issue #58 from two different repositories at once produces two
  sessions with the same name. `SendMessage` will ask you to disambiguate by ref rather than picking
  one, so steering is not silently misrouted — but the name alone will not tell them apart. Stagger
  such jobs, or steer by the ref the error quotes.

### Steering a running worker

A reporting worker is also *addressable*: it runs as `dispatch-issue-<n>` and accepts inbound
messages, so the foreman can correct it mid-run with its own `SendMessage` tool instead of stopping
and re-dispatching. Verified: a message sent to a running sandboxed worker arrived mid-run and
changed what it built.

Two things to expect:

- **It is racy.** The worker's socket disappears the moment it exits, so "worker already gone" is a
  normal outcome, not a failure. When it happens, fall back to `dispatch rework`, which appends
  instructions to the prompt for a fresh attempt.
- **The first send may be refused.** A session you did not spawn needs its ref confirmed; the error
  quotes the exact one to use, e.g. `dispatch-issue-58 [16ea81]`. Send once more with that.

A silent worker (`--no-report`, or any non-`claude` provider) is **not** addressable: it keeps the
original invocation exactly, with no name and no inbound acceptance.

---

## Operational facts (apply to all modes)

1. **The gate runs asynchronously after `DONE`.** The notification fires when the worker exits,
   not when the gate finishes. Check `.dispatch/jobs/<n>/gate.md` (or
   `.dispatch/jobs/<n>/attempts/<k>/gate.md` for a reworked job) before concluding no gate ran.

2. **Never commit into a gated job's worktree mid-run.** The rework loop re-runs the worker in
   the same worktree. A manual commit there will be included in the rework diff and confuse both
   the worker and the gate.

## See also

- [gate.md](gate.md) — how the headless gate works, verdict format, bounded rework details
- [usage.md](usage.md) — full CLI reference including `dispatch start`, `dispatch gate`, `dispatch rework`

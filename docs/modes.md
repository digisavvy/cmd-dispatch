# Foreman modes

The foreman has three named operating modes. Choose based on the issue's complexity and risk
profile. In dealer's choice (the default), the foreman picks for you and explains why.

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

---
description: Pick a model from a short plain-English menu and dispatch it to GitHub issues — no aliases to memorize.
---

Use this when the user wants to dispatch work but doesn't want to remember model aliases. You show a
short, curated menu and dispatch the chosen model. This is a friendlier front door to `dispatch start`
— the mechanical work is still the `dispatch` CLI. Run from inside the target repo (the one with the issues).

## 1. Get the issue(s)

Parse issue number(s) from the user's message (`/pick #41 #42`, "pick a model for 41 and 57"). If none
are given, ask which issue(s) to dispatch — don't guess.

## 2. Show the curated menu (AskUserQuestion)

Present exactly these six options — human labels, not slugs. Each maps to a `models.conf` alias:

| Menu label | alias | what it is |
|---|---|---|
| **Codex — Best** | `5.6` | frontier coding (gpt-5.6-sol); slowest/priciest |
| **Codex — Balanced** | `5.6-terra` | everyday work |
| **Codex — Fast** | `5.6-luna` | fast + affordable |
| **Claude — Best** | `opus` | frontier Claude |
| **Claude — Balanced** | `sonnet` | everyday Claude |
| **Claude — Fast** | `haiku` | fast + cheap Claude |

Use the "what it is" text as each option's detail. If several issues were given, first ask whether to
apply one model to all of them or pick per issue, then run the menu accordingly.

## 3. Dispatch

For each issue, run `dispatch start <issue#> <alias>` with the chosen alias, then report the job table
with `dispatch status`. From here it's the normal flow — `dispatch wait <n>`, review the diff,
`dispatch pr <n>`.

## Rules

- **Never make the user type an alias** — that's the entire point of this command.
- Only offer the six labels above; each alias must exist in `dispatch models`. If one is missing
  (someone edited `models.conf`), say so and fall back to the full `dispatch models` list.
- Inline intent wins — if the user already named a model ("best codex on #41"), skip the menu and map
  it straight to the alias.

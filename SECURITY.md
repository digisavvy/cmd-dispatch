# Security

## Trust model

`dispatch` is intended for repositories, issues, local configuration, and notification hooks that
you trust. A worker is an autonomous process with write access to its issue worktree and the target
repository's shared Git directory. The worktree and branch separate concurrent jobs, but they are
not a security boundary.

The default control is human review: workers commit but do not push, open pull requests, or merge.
Inspect the commit and worktree before running `dispatch pr`. The optional headless gate reduces
review effort but processes the same untrusted issue and diff with another model; it is not a
sandbox or a substitute for human review. It never merges automatically.

## Residual risks

- **Prompt injection:** GitHub issue titles and bodies are untrusted text embedded in worker and
  gate prompts. The worker prompt tells the model not to treat issue text as authority to escape the
  worktree or access credentials, but model instructions are not an enforceable security boundary.
- **Repository secrets:** workers can read the target worktree. Checked-out `.env` files, private
  keys, production configuration, and secrets committed to the repository may be exposed to the
  selected model provider or used by commands the worker runs. There is no optional denylist: a
  filename denylist would be incomplete and could also break legitimate builds.
- **Shared `.git` access:** linked-worktree commits require writing the common object store and refs,
  so supported workers receive the main repository's whole Git common directory via `--add-dir` (or
  the provider equivalent). This also permits changes to shared Git configuration and hooks; a
  malicious worker could persist code that runs during a later Git operation. Restricting access to
  `.git/worktrees/<name>` alone breaks commits because objects, refs, and their lock files remain in
  the common directory. A narrower portable allowlist would depend on Git internals and is not used.
- **Broad worker capabilities:** provider CLIs may run tools non-interactively. Provider sandboxes
  differ, and local credentials available to those CLIs remain in their own trust boundary.
- **Notification execution:** `DISPATCH_NOTIFY_CMD` deliberately executes a trusted local program.
  It is local configuration, not issue-controlled input, and receives issue-derived values only as
  quoted arguments and environment variables. It must name one executable; use a wrapper script for
  fixed flags. The wrapper must treat all `DISPATCH_*` values as untrusted data.

## Safe use

1. Run `dispatch` only for trusted repositories and review issue text before starting a worker.
2. Remove secrets from the checkout and use least-privilege, short-lived credentials for tools a
   worker may invoke. Prefer a separate machine or stronger external sandbox for hostile code.
3. Review the full commit, worktree status, and relevant shared Git configuration and hooks before
   pushing. Do not rely solely on the headless gate for security-sensitive changes.
4. Keep `.dispatch/` out of version control and writable only by the local user. Job metadata drives
   cleanup and other operations; `dispatch clean` validates its expected job, branch, and worktree
   paths before removal.
5. Configure `DISPATCH_NOTIFY_CMD` only from a trusted local environment. Never construct it from an
   issue, repository file, or other untrusted input.

To report a vulnerability, open a private security advisory in the GitHub repository rather than a
public issue when possible.

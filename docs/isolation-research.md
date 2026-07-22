# Lean worker isolation without containers

Research date: 2026-07-22. This note evaluates confinement for `dispatch` workers that execute
untrusted issue text. A linked Git worktree is an organization mechanism, not a security boundary:
without an OS policy, a child process retains the invoking user's filesystem and network access.

## Findings

| Mechanism | OS | What it confines | Effort | Important caveats |
| --- | --- | --- | --- | --- |
| Claude permission modes and tool rules | macOS/Linux | Claude tool calls and approval decisions | Low | Application policy, not an OS boundary. A permitted `Bash` can reach everything the process can reach. `--allowedTools` pre-approves matches; by itself it is not an allowlist. |
| Kimi permission rules/modes | macOS/Linux | Kimi built-in and MCP tool approvals | Low | Application policy, not an OS boundary. Prompt mode is unattended and permissive; rules can deny known tools but cannot confine a permitted shell process. |
| Seatbelt via `sandbox-exec` | macOS | Kernel-enforced file operations, process operations, and network operations selected by a profile | Medium | Still used by current sandbox launchers, but its own man page marks it **DEPRECATED**. The profile language is not a supported public API, profiles are easy to under-specify, and OS/CLI updates can break them. |
| Bubblewrap (`bwrap`) | Linux | Mount, user, PID, IPC, UTS, cgroup, and network namespaces; bind-mounted filesystem view | Medium | Lean and composable, but depends on usable user namespaces or a setuid installation. The host runtime, certificates, and an API egress path must be mounted deliberately. |
| Landlock | Linux | Unprivileged, inherited filesystem restrictions; newer ABIs also restrict TCP/UDP by port | Medium/high | Requires a launcher/library and kernel/ABI feature detection. It does not create a reduced filesystem view, and older ABIs omit important controls (for example truncate before ABI 3 and TCP before ABI 4). |
| Firejail | Linux | Namespace-based filesystem/network isolation plus seccomp/capability controls and profiles | Medium | Convenient packaged profiles, but a larger policy surface and another privileged/setuid-sensitive component on some distributions. Distribution configuration varies. |
| NsJail | Linux | Namespaces, read-only/custom mounts, cgroups, rlimits, and seccomp-bpf | High | Powerful, but more machinery and policy tuning than this use case needs; installation and unprivileged namespace support vary. |

The Linux feature summaries above follow the projects' own documentation: Bubblewrap exposes bind
mounts and `--unshare-net` in its [source/CLI help](https://github.com/containers/bubblewrap/blob/main/bubblewrap.c),
Landlock is a stackable unprivileged LSM whose rules are inherited by child processes
([kernel documentation](https://docs.kernel.org/userspace-api/landlock.html)), and NsJail combines
namespaces, mounts, cgroups, rlimits, and seccomp
([NsJail README](https://github.com/google/nsjail)). Firejail similarly documents filesystem
allowlisting (`private`, `whitelist`) and network namespaces in its
[manual](https://man7.org/linux/man-pages/man1/firejail.1.html).

## CLI controls verified

### Claude Code

Locally verified against `claude --help`, Claude Code 2.1.170:

- `-p`/`--print` is non-interactive and skips the workspace trust dialog.
- `--permission-mode` accepts `acceptEdits`, `auto`, `bypassPermissions`, `default`, `dontAsk`, and
  `plan`.
- `--allowedTools`/`--allowed-tools` and `--disallowedTools`/`--disallowed-tools` exist.
- `--add-dir` and `--dangerously-skip-permissions` exist. Dispatch currently invokes both, giving
  the worker access to its worktree and Git common directory while bypassing permission checks.

Anthropic documents that `acceptEdits` automatically accepts edits and common filesystem commands
in the working/additional directories, while `plan` is read-only. More useful for unattended work,
`dontAsk` denies calls that would otherwise prompt, so it can run headlessly with explicit allow
rules. Anthropic specifically recommends pairing a restricted allow set with `dontAsk` for CI.
However, `--allowedTools` alone only pre-approves matching tools: unmatched tools fall through to
the active mode. See [permission modes](https://code.claude.com/docs/en/permission-modes) and
[permission configuration](https://code.claude.com/docs/en/permissions).

Consequences for dispatch:

- `plan` cannot implement an issue.
- `acceptEdits` can edit without blocking, but arbitrary shell actions still need approval and a
  non-interactive run cannot be relied upon to grant it.
- `dontAsk` is predictably non-blocking, but allowing unrestricted `Bash` restores most of the risk;
  narrow command patterns are brittle for general coding work.
- Tool deny rules are useful defense in depth, not filesystem or network confinement.

### Kimi Code CLI

Locally verified against `kimi --help`, Kimi Code CLI 0.28.1:

- `-p`/`--prompt` runs one prompt non-interactively.
- `--yolo` auto-approves regular tool calls but may still ask questions; `--auto` is fully
  autonomous; `--plan` starts in plan mode.
- `--add-dir` exists. Dispatch currently uses prompt mode with the worktree as cwd and adds the Git
  common directory; it does not pass an explicit permission flag.

Current Kimi documentation says prompt mode cannot be combined with `--yolo`, `--auto`, or
`--plan` because prompt mode uses `auto` permission by default. Thus the current `-p` worker is
headless, but it auto-approves operations rather than confining them. Kimi's TOML configuration
supports `default_permission_mode` (`manual`, `yolo`, or `auto`) and ordered `[[permission.rules]]`
with `allow`, `deny`, or `ask` decisions and tool patterns such as `Bash(...)`. See the
[command reference](https://moonshotai.github.io/kimi-code/en/reference/kimi-command.html),
[approval flow](https://moonshotai.github.io/kimi-code/en/guides/interaction.html), and
[configuration reference](https://moonshotai.github.io/kimi-code/en/configuration/config-files.html).

Kimi's manual or plan modes can block waiting for approval and therefore do not fit the existing
unattended worker. A generated deny-rule configuration could reduce the tool surface, but a general
coding worker still needs write and command execution. As with Claude, Kimi rules do not constrain
the OS privileges of an allowed command.

## macOS Seatbelt feasibility

`/usr/bin/sandbox-exec` exists on the tested macOS 26.3.1 host. Its local man page describes `-f`
for a profile file, `-p` for a profile string, and `-D key=value` for profile parameters, while
stating twice that the command is deprecated and directing app developers to App Sandbox. A smoke
launch from inside this already-sandboxed research worker failed with `sandbox_apply: Operation not
permitted`, so nested execution was not verified here. Current projects including Anthropic's
sandbox runtime (linked below) demonstrate that the command still works when launched in an
appropriate host context. `[VERIFY]` Dispatch must confirm this on each supported, non-nested host;
there is no documented supported replacement that applies App Sandbox to an arbitrary CLI process.

Seatbelt can nevertheless wrap the entire CLI process tree, so a shell spawned by Claude or Kimi
inherits the policy. A starting **profile sketch**, not a production-ready profile, is:

```scheme
(version 1)
(allow default)

; Remove ambient writes, then add only dispatch-owned job paths.
(deny file-write*)
(allow file-write*
  (subpath (param "WORKTREE"))
  (subpath (param "GIT_COMMON"))
  (subpath (param "JOB_DIR"))
  (subpath (param "TMP_DIR")))

; Direct hosted API calls will fail under this rule.
(deny network*)
```

The wrapper would create a per-job temporary directory and profile, resolve all paths before launch,
then execute approximately:

```sh
sandbox-exec -f "$profile" \
  -D WORKTREE="$wt" -D GIT_COMMON="$gitcommon" \
  -D JOB_DIR="$jd" -D TMP_DIR="$job_tmp" \
  claude ...
```

The sketch deliberately uses `(allow default)` plus a write/network deny because executables,
dynamic libraries, certificates, and the CLI installation must remain readable. It therefore stops
host writes but **does not stop secret reads**. A stronger `(deny default)` profile would need an
audited read/execute allowlist for macOS runtime files, the Node/Python/runtime installation, CLI
files, certificates, the worktree, and Git metadata. That is feasible but brittle and must be tested
on every supported OS/CLI combination. The open-source
[Anthropic sandbox runtime](https://github.com/anthropic-experimental/sandbox-runtime) is useful
prior art: it generates Seatbelt profiles on macOS and mediates network access through local
proxies, but it is explicitly experimental and should be evaluated rather than silently adopted.

Profile validation must include negative tests from a child shell: writing in the worktree and Git
common directory succeeds; writing elsewhere fails; reading selected credential canaries fails in
the stronger profile; and direct TCP, UDP, Unix-socket, and localhost escape attempts fail as
intended. `[VERIFY]` Exact Seatbelt operation names and profile behavior across every supported
macOS release require an executable test suite because Apple does not publish the profile language
as a stable API.

## Network egress is inseparable from model access

`(deny network*)` on macOS or a fresh network namespace on Linux (`bwrap --unshare-net`, or the
equivalent Firejail/NsJail setting) prevents ordinary outbound secret exfiltration. It also prevents
Claude/Kimi from contacting their hosted model APIs, DNS, and authentication endpoints.

Allowing the model API directly is not a complete anti-exfiltration control: untrusted content can
instruct the worker to read a secret and include it in a model request. Hostname/IP allowlisting
also becomes fragile with DNS and CDN changes. A meaningful design therefore combines:

1. A sandbox with no direct network access.
2. A small local broker/proxy that is the only permitted socket endpoint.
3. Authentication held by the broker, not exposed in the worker environment or readable files.
4. Destination and method allowlisting, request-size/rate limits, logging, and ideally protocol-aware
   filtering of uploads.

Even a proxy cannot reliably distinguish source code needed for the task from a secret pasted into
a model prompt. The strongest lean control is therefore both a filesystem read boundary (secrets
are not visible) and mediated egress. Network denial alone is insufficient once any model channel
is reopened.

On Linux, a loopback-only/new network namespace can connect to a deliberately injected proxy via a
Unix socket or configured namespace link while having no default route. `[VERIFY]` The exact proxy
transport must be prototyped against Claude and Kimi authentication/API behavior; neither installed
CLI help output promises support for an arbitrary Unix-socket API transport.

## Recommendation for dispatch

Do not present per-CLI permission flags as the security boundary. For untrusted issues, use a
layered, opt-in `restricted` worker mode and fail closed when its OS launcher or policy tests are
unavailable:

1. **Immediate defense in depth:** replace Claude's bypass mode in restricted runs with
   `--permission-mode dontAsk` plus an explicit tool policy. Generate Kimi permission rules for the
   job rather than inheriting user/project rules. Disable unneeded MCP/plugin/config discovery for
   both CLIs where verified controls exist. This reduces accidental capability but will require
   provider-specific tuning to preserve general coding behavior.
2. **macOS pilot:** wrap the complete worker process in a generated Seatbelt profile. First ship
   write confinement to the resolved worktree, resolved Git common directory, dispatch job state,
   and a private temp directory. Move to deny-by-default reads only after runtime allowlists and
   negative tests are reliable. Label this backend experimental/deprecated and fail closed rather
   than falling back to an unsandboxed run.
3. **Linux backend:** prefer Bubblewrap for the first implementation: construct a read-only runtime
   view, bind the worktree/Git common/job temp paths read-write, use fresh PID/user/mount namespaces,
   and use `--unshare-net`. Detect disabled unprivileged user namespaces and fail closed. Landlock is
   an attractive later backend where installation constraints make Bubblewrap unsuitable; NsJail
   is justified only if dispatch also needs cgroups/seccomp/resource policy.
4. **Egress phase:** initially, no-network workers can support only providers with an already-local
   model endpoint. Before claiming hosted Claude/Kimi support is safe, add and test the credential-
   holding broker described above. Until then, describe hosted workers as filesystem-write-confined,
   not protected from secret exfiltration.

A rough dispatch implementation would add a provider-independent launcher that receives only
resolved absolute paths and an argv array. The launcher selects `seatbelt` or `bwrap`, builds a
per-job policy under `.dispatch/<issue>/`, scrubs the environment to a small allowlist, assigns a
private temporary/home directory, starts the provider, and records the backend/policy version in job
metadata. Startup self-tests exercise both allowed and forbidden operations before any untrusted
prompt is sent. `dispatch models` or a new diagnostics path should report whether restricted mode is
available; `dispatch start` must never silently downgrade it.

This is still lean—one small launcher and native OS primitives, no image lifecycle—but honest about
the residual risk. Seatbelt's deprecation makes it a pragmatic macOS bridge, not a permanent public
contract; Bubblewrap is the clearest Linux default; CLI permission rules remain a valuable second
layer rather than the isolation mechanism.

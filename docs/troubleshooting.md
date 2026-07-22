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

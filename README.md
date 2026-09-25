# github-action-go-proxy-pull

Composite action that warms a Go module proxy for the tag that triggered the
workflow.

## Overview

When a Go module is released, the first consumer to ask for the new version pays
for the proxy's fetch of it. Requesting the version immediately after the tag is
pushed moves that cost off the consumer: `proxy.golang.org` fetches and caches
the module, and `pkg.go.dev` picks it up.

The action creates a throwaway module in a temporary directory and runs
`go get <module>@<version>` in it. It does not check out, read or write the
calling repository.

### What it replaces, and why

This action replaces `andrewslotin/go-proxy-pull-action@v1.5.0`, which 28
senzing-garage Go repositories called from
`.github/workflows/go-proxy-pull.yaml`.

Three problems with that arrangement:

- It is a Docker action owned by an individual account, consumed at a **mutable
  tag**. Whoever controls that account can move `v1.5.0`, and the moved tag
  executes in CI on the next release of every one of those repos.
- The calling job granted it `contents: write` on a `push: tags` trigger. The
  action needs no write access of any kind, so an account takeover plus a retag
  was push access to the default branch of the whole Go fleet.
- Its entrypoint is 27 lines of shell. There is no benefit to sourcing that from
  outside the organization.

The replacement is first-party, so the supply-chain path is gone, and the
calling job needs **no permissions at all**.

### Why its own repository

It is a Go-only action, so it gets its own `senzing-factory/github-action-*`
repository rather than becoming a composite inside
`senzing-factory/build-resources`. `build-resources` is consumed by the Python,
Docker and shell repositories as well; a Go-only breaking change here must not
force a `build-resources` major bump on all of them. Where a shared action lives
is decided by version blast radius, not by size.

## Usage

The calling job needs `permissions: {}`. The action never touches the calling
repository, so the job's `GITHUB_TOKEN` needs no scopes.

In the calling repository, `.github/workflows/go-proxy-pull.yaml`:

```yaml
name: Go proxy pull

on:
  push:
    tags:
      - "v[0-9]+.[0-9]+.[0-9]+"

permissions: {}

jobs:
  go-proxy-pull:
    permissions: {}
    runs-on: ubuntu-latest
    timeout-minutes: 10

    steps:
      - name: Pull new module version
        uses: senzing-factory/github-action-go-proxy-pull@v1

      - name: Notify Slack on failure
        if: failure() || cancelled()
        uses: senzing-factory/build-resources/slack-failure-notification@v4
        with:
          job-status: ${{ job.status }}
          slack-channel: ${{ secrets.SLACK_CHANNEL }}
          slack-bot-token: ${{ secrets.SLACK_BOT_TOKEN }}
```

### Migrating from `andrewslotin/go-proxy-pull-action`

Three edits per repository:

1. Point `uses:` at `senzing-factory/github-action-go-proxy-pull@v1` instead of
   `andrewslotin/go-proxy-pull-action@v1.5.0`.
2. Drop the `with: import_path:` line — that value is the default here.
3. Replace the job's `permissions: contents: write` with `permissions: {}`.

The `import_path` input is not needed: the default module path is already
`github.com/<owner>/<repo>`. Keep an explicit path only where the module path
differs from the repository path, and note the input is spelled `import-path`
here, matching the hyphenated convention used by the other
`senzing-factory/github-action-*` actions.

## Inputs

| Name          | Default                    | Description                     |
| ------------- | -------------------------- | ------------------------------- |
| `goproxy`     | `https://proxy.golang.org` | Go module proxy to warm         |
| `import-path` | empty                      | Module path; empty means `M`    |
| `go-version`  | `1.26`                     | Go version used to run `go get` |
| `ref`         | `${{ github.ref }}`        | Tag ref the version comes from  |

`import-path` defaults to the empty string and the script substitutes
`github.com/<owner>/<repo>` for it, so passing an empty value is the same as
omitting the input. `ref` exists so the action can be exercised from a pull
request, where `github.ref` is `refs/pull/N/merge` and names no module version;
callers should leave it alone. If `ref` is passed as an empty value — or the
`${{ github.ref }}` default ever evaluates to empty — the script falls back to
the `GITHUB_REF` environment variable that GitHub Actions sets in every step, so
the path every caller uses cannot fail for want of a ref. A non-empty `ref`
always wins.

## Behavior

The module path and version are derived from the ref that triggered the run.
Below, `M` stands for the default module path `github.com/<owner>/<repo>`:

| Tag               | Module path     | Version  |
| ----------------- | --------------- | -------- |
| `v1.2.3`          | `M`             | `v1.2.3` |
| `v2.0.0`          | `M/v2`          | `v2.0.0` |
| `examples/v1.2.3` | `M/examples`    | `v1.2.3` |
| `examples/v3.0.0` | `M/examples/v3` | `v3.0.0` |

That is, a tag of the form `<submodule>/vX.Y.Z` releases a nested module and the
submodule directory joins the module path, and Go's requirement of a `/vN`
suffix for every major version above 1 is applied on top.

A ref that is not a tag ref is rejected with a clear error rather than turned
into a module path built out of `refs/heads/...`.

Note that the tag filter in the usage example above, `v[0-9]+.[0-9]+.[0-9]+`, is
what every existing caller uses, and it matches neither submodule tags nor
prerelease tags. A repository that releases nested modules has to widen its own
filter — for example `"*/v[0-9]+.[0-9]+.[0-9]+"` — before the submodule behavior
can ever fire.

The tag name reaches the script through the environment, never through `${{ }}`
interpolation into a `run:` block: anyone who can push a tag chooses its name,
and an interpolated tag name is shell code.

`actions/setup-go` exports `GOTOOLCHAIN=local`, which would make `go get` fail
outright once a module declares a newer `go` directive than the pinned
`go-version`. The action overrides it with `GOTOOLCHAIN: auto` on the step, so a
fleet-wide Go bump does not turn every release job red.

### Private and enterprise proxies

The action sets only `GOTOOLCHAIN`, `GOPROXY` and the script's own inputs on its
step, so any other Go environment variable set at the calling job's level
reaches `go get` unchanged. There is deliberately no input for these: they are
variables Go already defines, and an input would be a second spelling of them
that this action would owe a stable meaning for the life of `v1`.

That matters when `goproxy` points somewhere other than the public proxy. The
checksum database is consulted independently of `GOPROXY`, so a module that
`sum.golang.org` has never seen fails with `verifying module: ... 404 Not Found`
even though the proxy served it. Set `GOPRIVATE` to the matching module prefix
on the job:

```yaml
jobs:
  warm-proxy:
    runs-on: ubuntu-latest
    env:
      GOPRIVATE: github.example.com/*
    steps:
      - uses: senzing-factory/github-action-go-proxy-pull@v1
        with:
          goproxy: https://proxy.example.com
```

`GOPRIVATE` seeds both `GONOPROXY` and `GONOSUMDB`, so it is the one to reach
for first; set those two directly only when they need to differ from each other.
`GONOSUMCHECK` is not recognized by modern `cmd/go` and does nothing.

## Testing

`tests/resolve-package.bats` is a bats suite covering the ref-to-module-path
derivation — the submodule and major-version branches in particular. It sources
`go-proxy-pull.sh` and calls `resolve_package` directly:

```console
bats tests/
```

[.github/workflows/go-proxy-pull-test.yaml] runs it on Ubuntu and macOS on every
pull request, alongside four end-to-end jobs:

- one through the action itself, against a published module version;
- one driving the script directly with a submodule tag;
- one pinning `go-version` to 1.25 and pulling a module whose `go` directive is
  1.26, which fails if the `GOTOOLCHAIN` override is ever dropped;
- one that builds a throwaway module, serves it from a module proxy on
  `localhost`, points the action at that proxy and then asserts the proxy's own
  access log shows the module was requested and that a newer toolchain was
  fetched.

The first three pull modules `proxy.golang.org` cached long ago, so they show
the action exits 0 rather than that it did anything; the last one fails when the
action no-ops.

[.github/workflows/go-proxy-pull-test.yaml]: .github/workflows/go-proxy-pull-test.yaml

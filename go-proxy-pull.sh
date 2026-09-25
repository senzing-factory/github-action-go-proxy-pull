#!/usr/bin/env bash
# go-proxy-pull.sh -- warm a Go module proxy for the tag that triggered the run.
#
# Requesting a module version from proxy.golang.org is what causes the proxy to
# fetch and cache it, so the first real consumer of a new release does not have
# to wait for the fetch. Nothing here writes to the calling repository.
#
# Inputs, all from the environment:
#   REF                full git ref of the run, e.g. refs/tags/v1.2.3 (required;
#                      falls back to GITHUB_REF when empty or unset)
#   GITHUB_REF         the ref of the workflow run, set by GitHub Actions
#   REPO               <owner>/<repo>                                 (required)
#   INPUT_IMPORT_PATH  module path override; empty means github.com/$REPO
#   GOPROXY            proxy to warm; honored by `go get` itself
#
# The file is safe to source: every function returns rather than exits, no
# shell options are changed at load time, and main runs only when the script is
# executed directly. tests/resolve-package.bats does exactly that.

# resolve_package prints "<module path> <version>" for the current ref.
#
# Two shapes of tag exist:
#   v1.2.3              a release of the module at the repository root
#   <submodule>/v1.2.3  a release of a nested module; the module path gains
#                       the submodule directory
# and Go requires a /vN suffix on the module path for every major above 1.
resolve_package() {
  local ref="${REF-}" repo="${REPO-}" import_path="${INPUT_IMPORT_PATH-}"
  local tag version package major

  # The `ref` input defaults to ${{ github.ref }}, so REF normally arrives
  # filled in. An expression that evaluates to empty -- or the script being run
  # outside the composite action -- would otherwise fail the run outright, so
  # fall back to the ref GitHub Actions puts in the environment of every step.
  # A non-empty REF always wins: an explicit input is a deliberate override.
  if [[ -z "${ref}" ]]; then
    ref="${GITHUB_REF-}"
  fi

  if [[ -z "${ref}" ]]; then
    echo "[ERROR] REF is required" >&2
    return 1
  fi
  if [[ -z "${repo}" ]]; then
    echo "[ERROR] REPO is required" >&2
    return 1
  fi
  # Only a tag ref carries a module version. Any other ref would produce a
  # module path built out of "refs/heads/..." and a puzzling `go get` failure,
  # so say what is actually wrong instead.
  if [[ "${ref}" != refs/tags/* ]]; then
    echo "[ERROR] REF is not a tag ref: ${ref}" >&2
    return 1
  fi

  tag="${ref#refs/tags/}"
  version="${tag##*/}"
  package="${import_path:-github.com/${repo}}"

  # A tag that still has a slash in it after the version is stripped is a
  # submodule tag; everything before the version is the submodule directory.
  if [[ "${version}" != "${tag}" ]]; then
    package="${package}/${tag%"/${version}"}"
  fi

  # Major version suffix. 10# forces base 10 on the comparison so a tag such
  # as v08.1.0 is eight rather than an invalid octal literal; the suffix itself
  # keeps the digits as written. The digit test keeps a non-numeric tag (a
  # release-candidate stream, a date tag) from aborting in arithmetic
  # expansion -- such a tag simply gets no suffix, which is what go wants.
  major="${version#v}"
  major="${major%%.*}"
  if [[ "${major}" =~ ^[0-9]+$ ]] && ((10#${major} > 1)); then
    package="${package}/v${major}"
  fi

  printf '%s %s\n' "${package}" "${version}"
}

main() {
  local package version workdir resolved

  # Separate declaration and assignment: `local x="$(cmd)"` would mask a
  # non-zero exit from cmd, and a failure to resolve must stop the run rather
  # than fall through to `go get @`.
  resolved="$(resolve_package)"
  read -r package version <<<"${resolved}"

  # Same fallback resolve_package applied, so the log names the ref that was
  # actually used -- and so an unset REF does not trip `set -u` here after
  # resolve_package has already succeeded on GITHUB_REF.
  echo "[INFO] ref:         ${REF:-${GITHUB_REF-}}"
  echo "[INFO] module:      ${package}"
  echo "[INFO] version:     ${version}"
  echo "[INFO] goproxy:     ${GOPROXY:-<go default>}"
  echo "[INFO] gotoolchain: ${GOTOOLCHAIN:-<go default>}"

  # A throwaway module outside the workspace: `go get` needs a go.mod to write
  # to, and it must not be the calling repository's.
  workdir="$(mktemp -d)"
  cd "${workdir}"
  go mod init dummy
  go get "${package}@${version}"

  echo "[INFO] proxy warmed for ${package}@${version}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Set only on the executed path, so sourcing this file does not silently
  # change the shell options of whatever sourced it.
  set -euo pipefail
  main
fi

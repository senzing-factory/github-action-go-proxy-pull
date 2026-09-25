#!/usr/bin/env bats
#
# Tests for resolve_package in go-proxy-pull.sh -- the ref-to-module-path
# derivation. The submodule-tag and major-version-suffix branches are the parts
# that are easy to get wrong and impossible to notice failing in production: a
# wrong module path warms nothing while reporting success.

setup() {
  # Sourcing is side-effect free: go-proxy-pull.sh sets its shell options only
  # on the executed path, so nothing has to be handed back here.
  # shellcheck source=../go-proxy-pull.sh disable=SC1091
  source "${BATS_TEST_DIRNAME}/../go-proxy-pull.sh"

  export REPO="senzing-garage/go-helpers"
  export INPUT_IMPORT_PATH=""
  BASE="github.com/${REPO}"

  # REF falls back to GITHUB_REF, which is set in every GitHub Actions step --
  # including the one that runs this suite. Clearing it keeps each case in
  # charge of the ref under test whether the suite runs in CI or on a laptop.
  unset GITHUB_REF
}

# --- root module -----------------------------------------------------------

@test "v0 tag gets no major version suffix" {
  export REF="refs/tags/v0.9.1"
  run resolve_package
  [ "$status" -eq 0 ]
  [ "$output" = "${BASE} v0.9.1" ]
}

@test "v1 tag gets no major version suffix" {
  export REF="refs/tags/v1.2.3"
  run resolve_package
  [ "$status" -eq 0 ]
  [ "$output" = "${BASE} v1.2.3" ]
}

# --- major version suffix --------------------------------------------------

@test "v2 tag gains /v2" {
  export REF="refs/tags/v2.0.0"
  run resolve_package
  [ "$status" -eq 0 ]
  [ "$output" = "${BASE}/v2 v2.0.0" ]
}

@test "two-digit major gains /v10" {
  export REF="refs/tags/v10.4.1"
  run resolve_package
  [ "$status" -eq 0 ]
  [ "$output" = "${BASE}/v10 v10.4.1" ]
}

@test "leading zero in major is compared base 10, not octal" {
  # The suffix keeps the digits as written; only the comparison is forced to
  # base 10, so an 08 or 09 major does not abort in arithmetic expansion.
  export REF="refs/tags/v08.1.0"
  run resolve_package
  [ "$status" -eq 0 ]
  [ "$output" = "${BASE}/v08 v08.1.0" ]
}

# --- pre-release versions --------------------------------------------------

@test "v1 pre-release keeps the full version string" {
  export REF="refs/tags/v1.2.3-rc.1"
  run resolve_package
  [ "$status" -eq 0 ]
  [ "$output" = "${BASE} v1.2.3-rc.1" ]
}

@test "v2 pre-release still gains /v2" {
  export REF="refs/tags/v2.0.0-beta.1"
  run resolve_package
  [ "$status" -eq 0 ]
  [ "$output" = "${BASE}/v2 v2.0.0-beta.1" ]
}

# --- submodule tags --------------------------------------------------------

@test "submodule tag joins the submodule directory to the module path" {
  export REF="refs/tags/examples/v1.2.3"
  run resolve_package
  [ "$status" -eq 0 ]
  [ "$output" = "${BASE}/examples v1.2.3" ]
}

@test "submodule tag with major above 1 gains both segments" {
  export REF="refs/tags/examples/v3.0.0"
  run resolve_package
  [ "$status" -eq 0 ]
  [ "$output" = "${BASE}/examples/v3 v3.0.0" ]
}

@test "nested submodule tag" {
  export REF="refs/tags/a/b/v1.0.0"
  run resolve_package
  [ "$status" -eq 0 ]
  [ "$output" = "${BASE}/a/b v1.0.0" ]
}

@test "nested submodule tag with major above 1" {
  export REF="refs/tags/a/b/v2.1.0"
  run resolve_package
  [ "$status" -eq 0 ]
  [ "$output" = "${BASE}/a/b/v2 v2.1.0" ]
}

# --- import-path override --------------------------------------------------

@test "import-path replaces the default module path" {
  export REF="refs/tags/v1.0.0"
  export INPUT_IMPORT_PATH="example.com/mod"
  run resolve_package
  [ "$status" -eq 0 ]
  [ "$output" = "example.com/mod v1.0.0" ]
}

@test "import-path is still subject to the major version suffix" {
  export REF="refs/tags/v4.0.0"
  export INPUT_IMPORT_PATH="example.com/mod"
  run resolve_package
  [ "$status" -eq 0 ]
  [ "$output" = "example.com/mod/v4 v4.0.0" ]
}

@test "import-path is still subject to the submodule rule" {
  export REF="refs/tags/tools/v1.0.0"
  export INPUT_IMPORT_PATH="example.com/mod"
  run resolve_package
  [ "$status" -eq 0 ]
  [ "$output" = "example.com/mod/tools v1.0.0" ]
}

# --- defensive -------------------------------------------------------------

@test "non-numeric major does not abort and gets no suffix" {
  export REF="refs/tags/nightly"
  run resolve_package
  [ "$status" -eq 0 ]
  [ "$output" = "${BASE} nightly" ]
}

@test "missing REF is a hard error" {
  unset REF
  run resolve_package
  [ "$status" -ne 0 ]
}

@test "missing REPO is a hard error" {
  export REF="refs/tags/v1.0.0"
  unset REPO
  run resolve_package
  [ "$status" -ne 0 ]
}

@test "a branch ref is rejected rather than turned into a garbage path" {
  export REF="refs/heads/main"
  run resolve_package
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a tag ref"* ]]
}

@test "a pull request merge ref is rejected" {
  export REF="refs/pull/42/merge"
  run resolve_package
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a tag ref"* ]]
}

# --- GITHUB_REF fallback ---------------------------------------------------
#
# Every consumer calls the action with no inputs at all, so the `ref` input
# takes its ${{ github.ref }} default and REF is whatever that expression
# evaluated to. If it ever evaluates to empty the run must still resolve, from
# the GITHUB_REF that GitHub Actions sets in the environment of every step.

@test "empty REF falls back to GITHUB_REF" {
  export REF=""
  export GITHUB_REF="refs/tags/v1.2.3"
  run resolve_package
  [ "$status" -eq 0 ]
  [ "$output" = "${BASE} v1.2.3" ]
}

@test "unset REF falls back to GITHUB_REF" {
  unset REF
  export GITHUB_REF="refs/tags/v1.2.3"
  run resolve_package
  [ "$status" -eq 0 ]
  [ "$output" = "${BASE} v1.2.3" ]
}

@test "the GITHUB_REF fallback runs through the whole derivation" {
  # A fallback that only handled the simple case would warm the wrong module
  # for a submodule tag with a major above 1, and still report success.
  export REF=""
  export GITHUB_REF="refs/tags/examples/v3.0.0"
  run resolve_package
  [ "$status" -eq 0 ]
  [ "$output" = "${BASE}/examples/v3 v3.0.0" ]
}

@test "a non-tag GITHUB_REF is rejected like a non-tag REF" {
  export REF=""
  export GITHUB_REF="refs/heads/main"
  run resolve_package
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a tag ref"* ]]
}

@test "a pull request merge GITHUB_REF is rejected" {
  export REF=""
  export GITHUB_REF="refs/pull/42/merge"
  run resolve_package
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a tag ref"* ]]
}

@test "empty REF with no GITHUB_REF is still a hard error" {
  export REF=""
  unset GITHUB_REF
  run resolve_package
  [ "$status" -ne 0 ]
  [[ "$output" == *"REF is required"* ]]
}

@test "a non-empty REF wins over GITHUB_REF" {
  export REF="refs/tags/v1.2.3"
  export GITHUB_REF="refs/tags/v9.9.9"
  run resolve_package
  [ "$status" -eq 0 ]
  [ "$output" = "${BASE} v1.2.3" ]
}

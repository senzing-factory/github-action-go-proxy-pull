# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog], [markdownlint], and this project
adheres to [Semantic Versioning].

## [Unreleased]

-

## [1.0.0] - 2026-09-25

### Added to 1.0.0

- Initial release. Replaces `andrewslotin/go-proxy-pull-action@v1.5.0` with a
  first-party composite action that needs no permissions on the calling job.
- `ref` falls back to the `GITHUB_REF` environment variable when the input is
  empty or unset. A non-empty `ref` still wins, so an explicit input remains a
  deliberate override.
- `GOTOOLCHAIN: auto` overrides the `GOTOOLCHAIN=local` that `actions/setup-go`
  exports, which would otherwise fail `go get` for any module declaring a `go`
  directive newer than the pinned `go-version`.
- Test suite: 26 bats cases covering the ref-to-module-path derivation, and five
  CI jobs including a regression test for the `GOTOOLCHAIN` override and an
  end-to-end job that serves a module from a controlled proxy and asserts the
  pull against the proxy's own access log.
- Documented that `GOPRIVATE` and friends set as job-level `env:` reach `go get`
  unchanged, so a private or enterprise `goproxy` needs no new input.

[Keep a Changelog]: https://keepachangelog.com/en/1.0.0/
[markdownlint]: https://github.com/DavidAnson/markdownlint
[Semantic Versioning]: https://semver.org/spec/v2.0.0.html

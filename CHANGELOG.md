# Changelog

All notable changes to this fork are documented in this file.

## [v1.14.2] — 2026-05-19

### Fixed
- **Volume snapshot tag filtering.** Skip tags whose key or value violates Alibaba Cloud ECS tag restrictions, which were causing snapshot creation to fail with malformed-tag errors.
  - Reject keys/values starting with `acs:` or `aliyun` (system-reserved prefixes). [`6df34d2`]
  - Reject keys/values containing `http://` or `https://`. [`6012ea8`]
  - New helper `isInvalidTag` in `velero-plugin-alibabacloud/volume_snapshotter.go`.

### Changed
- **Dockerfile.** Rewritten for a smaller, simpler build:
  - Base image: `golang:1.25.5` → `golang:1.25-bookworm`; runtime: `alpine:3.22` → `scratch`.
  - Removed BuildKit cache mounts and most ARGs; rely on standard `TARGETOS` / `TARGETARCH` from buildx.
  - Binary renamed `velero-plugin-alibabacloud` → `velero-plugin-for-alibabacloud`.
  - `ENTRYPOINT` switched from `cp /plugins/* /target/.` to direct exec of the binary.
- **build.sh.** Multi-arch buildx wrapper. Image repo and tag are parameterized (`./build.sh <tag>`; `IMAGE=` / `PLATFORMS=` overridable via env).

### Image

- `guswong/velero-plugin-for-alibabacloud:v1.14.2` (linux/amd64, linux/arm64).
- Built from `internal` (rebased onto `master`).
- Verifiable with `./hack/verify-image.sh <image-or-tar>` (looks for `vcs.revision` and the `isInvalidTag` symbol).

### Tracking

- Internal ticket: HC01-664991. Build artifacts live on the `internal` branch (rebased on `master`).
- The previously published `v1.14.1` was built from commit `1b0cc14` (pre-patch); it does **not** contain these fixes. Use `v1.14.2` or later.

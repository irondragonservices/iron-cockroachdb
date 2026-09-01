# irondragonservices/iron-cockroachdb

Hardened CockroachDB image.

Forked from [ironpeakservices/iron-cockroachdb](https://github.com/ironpeakservices/iron-cockroachdb).

The official `cockroach` binary and the libraries it links against, in a
`scratch` image — no shell, no package manager, nothing else at all. Runs as
uid 1000, listens on 26257 and 8080, stores data in
`/cockroach/cockroach-data`.

```sh
docker pull ghcr.io/irondragonservices/iron-cockroachdb:26
```

The tag tracks the CockroachDB release, so `:26.2.6` is built on
`cockroachdb/cockroach:v26.2.6`.

> **Licence.** CockroachDB ships under the CockroachDB Software Licence, not an
> OSI-approved one. The binary in this image is the official CCL distribution
> and that licence governs its use. This repository's own Apache-2.0 licence
> covers the packaging, not the database.

## Using it

```sh
docker run -v crdb-data:/cockroach/cockroach-data \
  ghcr.io/irondragonservices/iron-cockroachdb:26 \
  start-single-node --insecure
```

The entrypoint is `cockroach` itself, so every subcommand works as documented.
There is no shell, so `docker exec sh` will not; `cockroach sql` runs directly.

The container healthcheck assumes `--insecure`. **Override `HEALTHCHECK` when
running with certificates**, or it will report a healthy node as unhealthy.

## Verifying what you pulled

```sh
cosign verify ghcr.io/irondragonservices/iron-cockroachdb:26 \
  --certificate-identity-regexp '^https://github.com/irondragonservices/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Changes from upstream

- **The binary is no longer downloaded separately.** Upstream read the version
  out of the official image, then fetched
  `cockroach-${version}.linux-musl-amd64.tgz` from `binaries.cockroachdb.com`
  with no signature and no checksum check. The official image is the same
  artefact from the same vendor over an authenticated channel — and it has an
  arm64 manifest, which the tarball URL did not.
- **The image could only build for amd64**, for the same reason.
- **Libraries are resolved with `ldd`**, including the interpreter line, which
  has no `=>` and is the one thing a scratch image cannot start without.
- CockroachDB 21.2.0 to 26.2.6; the Alpine helper stage 3.16.3 to 3.24.1.
- CI rebuilt as callers into
  [irondragonservices/.github](https://github.com/irondragonservices/.github).

Verified on build: `start-single-node --insecure` initialises a cluster and the
container healthcheck reaches `healthy`.

## A note on amd64

CockroachDB's official image is built on RHEL and its glibc requires the
`x86-64-v3` instruction set. That is upstream's choice and this image inherits
it: on an amd64 host older than roughly Haswell, it exits with
`Fatal glibc error: CPU does not support x86-64-v3`. arm64 has no such
requirement.

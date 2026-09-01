# Everything a scratch image cannot provide for itself: an unprivileged
# account, CA certificates, timezone data, and the data directory with the
# right ownership and mode. Nothing from this stage ends up executable.
FROM alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b AS builder

# hadolint ignore=DL3018
RUN apk upgrade --no-cache \
  && apk add --no-cache ca-certificates tzdata

RUN adduser -s /bin/true -u 1000 -D -h /cockroach app \
  && sed -i -r "/^(app|root)/!d" /etc/group /etc/passwd \
  && sed -i -r 's#^(.*):[^:]*$#\1:/sbin/nologin#' /etc/passwd \
  && mkdir -p /out/cockroach/cockroach-data \
  && chown -R 1000:1000 /out/cockroach \
  && chmod -R 700 /out/cockroach

#
# ---
#

# The official CockroachDB image, for the binary and the libraries it needs.
#
# Upstream downloaded cockroach-${version}.linux-musl-amd64.tgz from
# binaries.cockroachdb.com instead, with no signature or checksum check and no
# architecture other than amd64. The official image is the same artefact from
# the same vendor, already fetched over an authenticated channel, and it has an
# arm64 manifest.
FROM cockroachdb/cockroach:v26.3.1@sha256:204f131510c78393adb02345f289a8dbb32e1491e26cc92b6c7751f3b97be3c5 AS cdb

# Fail the whole pipeline on the first failure. Without this the `ldd | awk |
# while read` below reports success even when ldd finds nothing, and the image
# is built missing every library it was supposed to carry.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Copy the binary and everything it links against, preserving paths, so the
# dynamic loader finds them at the same absolute paths inside scratch.
#
# The awk takes the first token on each ldd line that starts with a slash. That
# catches both the "libc.so.6 => /lib64/libc.so.6" form and the bare
# interpreter line, which has no "=>" and is the one thing the image cannot
# start without. linux-vdso has no path and drops out on its own.
RUN mkdir -p /out \
    && cp -a --parents /cockroach/cockroach /out \
    && ldd /cockroach/cockroach \
       | awk '{for (i = 1; i <= NF; i++) if ($i ~ /^\//) { print $i; break } }' \
       | sort -u \
       | while read -r lib; do \
           cp -a --parents "$lib" /out; \
           target="$(readlink -f "$lib")"; \
           [ "$target" != "$lib" ] && cp -a --parents "$target" /out; \
           true; \
         done

#
# ---
#

FROM scratch

LABEL org.opencontainers.image.source="https://github.com/irondragonservices/iron-cockroachdb"
LABEL org.opencontainers.image.description="Hardened base image for running CockroachDB"

ENV COCKROACH_CHANNEL=official-docker

# add-in our unprivileged user
COPY --from=builder /etc/passwd /etc/group /etc/shadow /etc/

# add-in timezone data
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo

# add-in our CA certificates, to validate the ones we connect to
COPY --from=builder /etc/ssl/certs/ /etc/ssl/certs/

# the working and data directories, owned by the runtime user
COPY --from=builder --chown=1000:1000 /out/cockroach /cockroach

# cockroach and the libraries it links against
COPY --from=cdb /out /

# run as our unprivileged user instead of root
USER app

WORKDIR /cockroach/

# SQL and the admin UI
EXPOSE 26257 8080

# persistent storage
VOLUME /cockroach/cockroach-data

# The healthcheck assumes --insecure. Override it when running with
# certificates, or it reports a healthy node as unhealthy.
HEALTHCHECK --interval=10s --timeout=10s --start-period=5s --retries=3 \
  CMD [ "/cockroach/cockroach", "sql", "--insecure", "-e", "SELECT 1" ]

ENTRYPOINT ["/cockroach/cockroach"]

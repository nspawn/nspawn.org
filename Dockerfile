# Development image for the nspawn.org website.
#
# Docsy needs Node.js, npm, Go and git; this image bundles them so the host only needs
# nspawn. compose.yaml mounts the repository into it and serves the site on port 1313.
FROM node:24-bookworm-slim

COPY --from=golang:1.25-bookworm /usr/local/go /usr/local/go
ENV PATH=/usr/local/go/bin:$PATH

RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /cache && chmod 1777 /cache

# Module, npm and Hugo caches live in the /cache volume (see compose.yaml) so that a
# restart of the container does not download everything again.
ENV HOME=/cache \
    GOPATH=/cache/go \
    GOMODCACHE=/cache/go/pkg/mod \
    GOCACHE=/cache/go-build \
    GOFLAGS=-buildvcs=false \
    HUGO_CACHEDIR=/cache/hugo \
    npm_config_cache=/cache/npm

WORKDIR /site
EXPOSE 1313

# Install the pinned dependencies (lock-exact, script-free; the Hugo binary self-installs
# on first use) and serve with live reload, reachable from outside the container.
CMD ["sh", "-c", "npm run install:safe && exec npm run serve:container"]

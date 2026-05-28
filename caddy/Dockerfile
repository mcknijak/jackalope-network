# Build Caddy with the Porkbun DNS provider plugin baked in.
# Rebuild whenever you want to update Caddy or pull a newer plugin:
#   docker compose build --no-cache && docker compose up -d

FROM caddy:2-builder AS builder
RUN xcaddy build \
    --with github.com/caddy-dns/porkbun

FROM caddy:2
COPY --from=builder /usr/bin/caddy /usr/bin/caddy

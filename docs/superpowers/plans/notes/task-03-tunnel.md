# Architecture change: Cloudflare Tunnel replaces Origin CA + reverse proxy

**Changed:** 2026-09-07, at the user's prompting. Supersedes spec section 2
(DNS and TLS) and the whole of plan Task 3.

## Why

The original design exposed the Synology on port 443, terminated TLS there with
a Cloudflare Origin CA certificate, reverse-proxied to node2, and kept the
public A record current with a DDNS container.

Cloudflare Tunnel makes a single **outbound** connection from node2 to
Cloudflare's edge. Nothing dials in.

## What this deleted

| Component | Before | Now |
|---|---|---|
| DSM certificate import | required | not used |
| DSM reverse proxy rule | required | not used |
| Cloudflare SSL mode Full (strict) | required | irrelevant — no origin leg |
| Inbound 443 port forward | required | **none** |
| `yukis-ddns` container | required | **removed** |
| Origin reachable from internet | yes, at the WAN IP | **no** |

The Origin CA certificate (valid to 2041) stays imported as an unused fallback.

## What it did not change

Tunnel is connectivity, not authorization. **Cloudflare Access still does the
authentication**, and was already configured on this account — team domain
`future-2808.cloudflareaccess.com`. Unauthenticated requests are redirected to
the Access login and never reach node2 at all.

## Configuration

Tunnel `kennel`, id `d215d6ac-8abe-41a1-8183-13463e855e11`.

Verified before use that this tunnel had exactly one connector — ours — so it is
not shared with another origin. A second tunnel, `waveplan`, exists on the
account with no connectors and is unrelated.

Ingress:

```json
[{"hostname": "control.yukisrescue.org", "service": "http://wordpress:80"},
 {"service": "http_status:404"}]
```

`http://wordpress:80` is the compose service name; cloudflared and WordPress
share the `wordpress_default` network. cloudflared forwards the original Host
header, so WordPress sees `control.yukisrescue.org` and the wp-config proxy
handling applies unchanged.

DNS: the DDNS-managed A record was deleted and replaced with a proxied CNAME to
`d215d6ac-8abe-41a1-8183-13463e855e11.cfargotunnel.com`.

## Interaction with the Simply Static fix

The Task 8 fix is what keeps publishing working under Access. Exports fetch
`127.0.0.1` inside the container and never traverse Cloudflare, so Access never
sees them. Had the crawler still gone out through Cloudflare, enabling Access
would have broken every export with a 302-shaped failure.

## Outstanding risk: token lifetime

The **only** token carrying `Cloudflare Tunnel: Edit` is `dev`, which **expires
2026-09-14**. After that, ingress changes require a new token. Move the scope to
a long-lived token, or accept that tunnel edits need a fresh credential.

Note the deploy token used by GitHub Actions deliberately does *not* carry
tunnel permissions: a CI secret should not be able to reshape the network.

## Synology teardown (safe once verified)

1. Remove the reverse proxy rule for `control.yukisrescue.org`
2. Unbind the Origin CA certificate from that service; keep the cert imported
3. **Leave the 443 port-forward** if any other host still uses it

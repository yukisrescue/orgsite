# WordPress Authoring Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give three web designers a WordPress UI at `control.yukisrescue.org` where they author content and publish it themselves to the existing static production site at `www.yukisrescue.org`.

**Architecture:** WordPress runs in Docker on node2 as an authoring tool only. A static export of the site is committed to this repository, and GitHub Actions deploys that export to Cloudflare Workers. Production is static and never depends on home hardware; a node2 or ISP outage stops publishing, not serving.

**Tech Stack:** Docker Compose, WordPress 6.x (`php8.3-apache`), MariaDB 11, Simply Static (free tier), Synology DSM reverse proxy, Cloudflare (Workers, DNS, Access, Turnstile), GitHub Actions, `wrangler` 4.x, Resend.

**Spec:** `docs/superpowers/specs/2026-09-06-wordpress-authoring-pipeline-design.md`

## Global Constraints

- **Host:** node2. Compose project directory `/opt/wordpress` on node2 (matches the `/opt/observability` convention on non-Mac hosts).
- **Portability is a construction constraint.** No Synology-specific bind mounts, no host paths outside the compose directory, all configuration via `.env`. Relocating to a VPS must be: `docker compose down`, rsync volumes, `docker compose up`, repoint DNS.
- **Compose conventions** follow `observability/`: explicit `container_name`, `restart: unless-stopped`, named volumes, `kickoff.sh` / `stop.sh` entry points.
- **Authoring hostname:** `control.yukisrescue.org`, Cloudflare-**proxied** (orange cloud). Non-negotiable — the Origin CA certificate is trusted only by Cloudflare's proxy.
- **Production hostname:** `www.yukisrescue.org`, Cloudflare Workers, worker name `yukis-rescue-org`.
- **Cloudflare account ID:** `b6add582162cf7189dd6cfa6bf5f001d`
- **Cloudflare tokens are account-owned.** They verify at `/accounts/{account_id}/tokens/verify`, **not** `/user/tokens/verify`, which returns 401 for them.
- **Credentials** live in `~/workspace/yukis/` on the operator Mac, mode `600`, outside any git repository: `zone_data.yml`, `tokens.yml`, `github_key.yml`, `designer_emails.yml`. Never copy these into the repo, a dotfile, or any document.
- **`dev` Cloudflare token expires 2026-09-14.** Long-lived tokens: `workers` and `dns`, both 2027-09-07.
- **SSL/TLS mode:** Full (strict).
- **Certificate:** existing Cloudflare Origin CA pair, `*.yukisrescue.org` + apex, valid to 2041-02-27. No renewal automation.
- **Designer WordPress role:** Editor. Exactly one Administrator (the owner).
- **Design tokens** (reproduce current site exactly): primary gradient `#667eea` → `#764ba2` at 135°; body text `#333`; card surface `#f8f9fa`; footer `#2d3748`; font stack `'Segoe UI', Tahoma, Geneva, Verdana, sans-serif`; container `1200px`; card radius `10px`; button radius `50px`.
- **Confirmed footer content** (verified accurate by an owner 2026-09-06): 1221 Coral Reef Place, Alameda, CA · 510.350.6924 · EIN 41-4413466 · 501(c)(3).
- **Backups:** `/media/assets/server/backup/wordpress` on the NAS.
- **Do not reproduce** the Vercel design at `yukis-rescue-org.vercel.app`. Unmerged third-party work, no source access.
- **Infrastructure verification replaces unit tests** where no code is under test. Every such step states an exact command and its expected output. "It looked fine" is not a pass.

---

## File Structure

**Created on node2 at `/opt/wordpress/`** (mirrored in this repo under `deploy/wordpress/`, secrets excluded):

| File | Responsibility |
|---|---|
| `docker-compose.yml` | WordPress, MariaDB, DDNS services |
| `.env.example` | Every variable, with safe placeholder values |
| `.env` | Real values. **Never committed.** |
| `kickoff.sh` / `stop.sh` | Stack lifecycle, matching `observability/` convention |
| `publish.sh` | Export → git commit → push |
| `watch-export.sh` | Detects a completed export, invokes `publish.sh` |
| `backup.sh` | Nightly database + uploads dump |
| `restore.sh` | Documented, exercised restore path |
| `tests/test-publish.sh` | Assertions for `publish.sh` against fixtures |
| `tests/test-backup.sh` | Assertions for `backup.sh` against fixtures |

**Created in this repository:**

| File | Responsibility |
|---|---|
| `deploy/wordpress/*` | Copies of the above, minus secrets |
| `theme/yukis/*` | Block theme source (`theme.json`, templates, patterns) |
| `site/` | Static export output. Deploy source of truth. |
| `legacy/` | The current hand-written HTML, retained for reference |
| `.github/workflows/deploy.yml` | Publishes `site/` to Cloudflare Workers |
| `worker-contact/` | Contact-form Worker (source, config, tests) |
| `wrangler.jsonc` | Modified: assets directory `./` → `./site` |

---

## Task 1: Verify build prerequisites on node2

Nothing else in this plan is safe to start until these facts are measured rather than assumed.

**Files:**
- Create: `docs/superpowers/plans/notes/task-01-prereqs.md` (record findings here; later tasks read it)

**Interfaces:**
- Produces: recorded values for `NODE2_HOST`, Docker version, free disk on the volume backing `/var/lib/docker`, an unused host port for WordPress (default assumption `8080`), and the promtail config filename in use on node2.

- [ ] **Step 1: Confirm SSH reachability and identity**

```bash
ssh node2.lan 'hostname; uname -a; id'
```

Expected: hostname reports `node2`. If SSH prompts for a password or fails, stop and resolve access before continuing — every later task depends on it.

- [ ] **Step 2: Confirm Docker is present and usable by this account**

```bash
ssh node2.lan 'docker version --format "{{.Server.Version}}"; docker compose version'
```

Expected: a server version prints without `permission denied`. If Docker is root-only for this user (as documented for `seshat.lan` in `observability/promtail/hosts.ini`), record that — every `docker` command in this plan then needs `sudo`.

- [ ] **Step 3: Confirm disk headroom**

```bash
ssh node2.lan 'df -h /var/lib/docker; df -h /opt'
```

Expected: at least 10GB free. WordPress, MariaDB, and uploads are small, but database backups and export history accumulate.

- [ ] **Step 4: Find a free host port**

```bash
ssh node2.lan 'ss -ltnp | grep -E ":(8080|8081|8090) " || echo "8080 8081 8090 all free"'
```

Expected: identify one unused port. Record it as `WP_HOST_PORT`. This plan assumes `8080`.

- [ ] **Step 5: Confirm NAS backup path is mounted**

```bash
ssh node2.lan 'ls -ld /media/assets/server/backup/ && touch /media/assets/server/backup/.writetest && rm /media/assets/server/backup/.writetest && echo WRITABLE'
```

Expected: `WRITABLE`. If the path does not exist or is read-only, Task 13 is blocked — record it now rather than discovering it at backup time.

- [ ] **Step 6: Locate the promtail config that node2 actually uses**

```bash
ssh node2.lan 'docker inspect promtail --format "{{json .Config.Cmd}}"; ls /opt/observability/promtail/config/'
```

Expected: the `-config.file` argument names a per-node file such as `promtail-node2.yml`. Record the exact filename — Task 2 edits it.

- [ ] **Step 7: Record findings and commit**

Write every measured value into `docs/superpowers/plans/notes/task-01-prereqs.md`. Later tasks read this file rather than re-measuring.

```bash
git add docs/superpowers/plans/notes/task-01-prereqs.md
git commit -m "docs: record node2 prerequisites for WordPress stack"
```

---

## Task 2: WordPress stack on node2

**Files:**
- Create: `deploy/wordpress/docker-compose.yml`
- Create: `deploy/wordpress/.env.example`
- Create: `deploy/wordpress/kickoff.sh`
- Create: `deploy/wordpress/stop.sh`
- Create: `deploy/wordpress/.gitignore`
- Modify (on node2, not in repo): the promtail config file identified in Task 1

**Interfaces:**
- Consumes: `WP_HOST_PORT` and the promtail config filename from Task 1.
- Produces: containers named `yukis-wordpress`, `yukis-mariadb`, `yukis-ddns`; WordPress reachable at `http://node2.lan:8080`; named volumes `wp_db`, `wp_uploads`, `wp_themes`.

- [ ] **Step 1: Write the compose file**

Create `deploy/wordpress/docker-compose.yml`:

```yaml
services:
  mariadb:
    image: mariadb:11
    container_name: yukis-mariadb
    environment:
      MARIADB_DATABASE: ${WP_DB_NAME}
      MARIADB_USER: ${WP_DB_USER}
      MARIADB_PASSWORD: ${WP_DB_PASSWORD}
      MARIADB_ROOT_PASSWORD: ${WP_DB_ROOT_PASSWORD}
    volumes:
      - wp_db:/var/lib/mysql
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 10s
      timeout: 5s
      retries: 12
    restart: unless-stopped

  wordpress:
    image: wordpress:6-php8.3-apache
    container_name: yukis-wordpress
    depends_on:
      mariadb:
        condition: service_healthy
    ports:
      - "${WP_HOST_PORT}:80"
    environment:
      WORDPRESS_DB_HOST: mariadb:3306
      WORDPRESS_DB_NAME: ${WP_DB_NAME}
      WORDPRESS_DB_USER: ${WP_DB_USER}
      WORDPRESS_DB_PASSWORD: ${WP_DB_PASSWORD}
      WORDPRESS_CONFIG_EXTRA: |
        if (isset($$_SERVER['HTTP_X_FORWARDED_PROTO']) && $$_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
            $$_SERVER['HTTPS'] = 'on';
        }
        define('WP_HOME',    '${WP_PUBLIC_URL}');
        define('WP_SITEURL', '${WP_PUBLIC_URL}');
        define('FORCE_SSL_ADMIN', true);
        define('DISALLOW_FILE_EDIT', true);
    volumes:
      - wp_uploads:/var/www/html/wp-content/uploads
      - wp_themes:/var/www/html/wp-content/themes
      - wp_export:/var/www/html/wp-content/uploads/simply-static
    restart: unless-stopped

  ddns:
    image: favonia/cloudflare-ddns:latest
    container_name: yukis-ddns
    network_mode: host
    user: "1000:1000"
    read_only: true
    cap_drop: [all]
    security_opt: [no-new-privileges:true]
    environment:
      CLOUDFLARE_API_TOKEN: ${CF_DNS_TOKEN}
      DOMAINS: control.yukisrescue.org
      PROXIED: "true"
      IP6_PROVIDER: none
    restart: unless-stopped

volumes:
  wp_db:
  wp_uploads:
  wp_themes:
  wp_export:
```

Two details that cause silent failures if changed:

- `$$_SERVER` — Compose interpolates `$`, so the PHP variable must be escaped as `$$`. A single `$` produces a `wp-config.php` with an empty variable and WordPress will redirect-loop behind the proxy.
- `PROXIED: "true"` — if this becomes `false`, the DNS record goes grey-cloud, the Origin CA certificate stops being trusted, and the site breaks with a certificate error.

- [ ] **Step 2: Write `.env.example`**

Create `deploy/wordpress/.env.example`:

```bash
# Copy to .env on node2 and fill in. Never commit .env.
WP_DB_NAME=wordpress
WP_DB_USER=wordpress
WP_DB_PASSWORD=CHANGEME_generate_with_openssl_rand_base64_24
WP_DB_ROOT_PASSWORD=CHANGEME_generate_with_openssl_rand_base64_24
WP_HOST_PORT=8080
WP_PUBLIC_URL=https://control.yukisrescue.org
# Cloudflare token with Zone:DNS:Edit + Zone:Zone:Read on yukisrescue.org
CF_DNS_TOKEN=CHANGEME
```

- [ ] **Step 3: Write the gitignore that keeps secrets out**

Create `deploy/wordpress/.gitignore`:

```
.env
```

- [ ] **Step 4: Write lifecycle scripts**

Create `deploy/wordpress/kickoff.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
[ -f .env ] || { echo "ERROR: .env missing. Copy .env.example and fill it in." >&2; exit 1; }
docker compose up -d
echo "WordPress stack up."
```

Create `deploy/wordpress/stop.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
docker compose down
echo "WordPress stack stopped."
```

```bash
chmod +x deploy/wordpress/kickoff.sh deploy/wordpress/stop.sh
```

- [ ] **Step 5: Verify the compose file parses before shipping it**

```bash
cd deploy/wordpress && cp .env.example .env.tmp && \
  docker compose --env-file .env.tmp config >/dev/null && echo "COMPOSE VALID" && rm .env.tmp
```

Expected: `COMPOSE VALID`. This catches the `$$` escaping mistake immediately.

- [ ] **Step 6: Deploy to node2 and start**

```bash
ssh node2.lan 'mkdir -p /opt/wordpress'
rsync -av --exclude .env deploy/wordpress/ node2.lan:/opt/wordpress/
ssh node2.lan 'cd /opt/wordpress && cp .env.example .env'
```

Now edit `/opt/wordpress/.env` on node2 with real values. Generate passwords with `openssl rand -base64 24`. Take `CF_DNS_TOKEN` from the `dns` entry in `~/workspace/yukis/tokens.yml` — read it into the file directly, do not echo it to a terminal.

```bash
ssh node2.lan 'chmod 600 /opt/wordpress/.env && cd /opt/wordpress && ./kickoff.sh'
```

- [ ] **Step 7: Verify WordPress responds**

```bash
ssh node2.lan 'sleep 20; curl -sS -o /dev/null -w "%{http_code} %{redirect_url}\n" http://localhost:8080/wp-admin/install.php'
```

Expected: `200` — the installer page. A `500` means the database is not ready; check `docker logs yukis-wordpress`.

- [ ] **Step 8: Verify DDNS created a proxied record**

```bash
ssh node2.lan 'docker logs yukis-ddns --tail 20'
```

Expected: a line reporting the record was set. Then confirm from the Cloudflare side:

```bash
cd ~/workspace/yukis && python3 -c "
import re,json,urllib.request
z=[l.split(':')[1].strip() for l in open('zone_data.yml') if l.startswith('zone_id')][0]
t=None;cur=None
for l in open('tokens.yml'):
    m=re.match(r'^\s{2}(\w+):',l); cur=m.group(1) if m else cur
    m2=re.match(r'^\s{4}token:\s*(\S+)',l)
    if m2 and cur=='dns': t=m2.group(1)
r=urllib.request.Request(f'https://api.cloudflare.com/client/v4/zones/{z}/dns_records?name=control.yukisrescue.org',headers={'Authorization':'Bearer '+t})
d=json.load(urllib.request.urlopen(r))
for rec in d['result']: print(rec['type'], rec['name'], 'proxied=',rec['proxied'])
"
```

Expected: `A control.yukisrescue.org proxied= True`. **If `proxied` is False, stop and fix it** — everything downstream assumes Cloudflare terminates the public connection.

- [ ] **Step 9: Add the containers to promtail's scrape allowlist**

On node2, edit the promtail config file identified in Task 1. Find the `keep` relabel rule:

```yaml
      - source_labels: [__meta_docker_container_name]
        regex: '/(rknn-lcm-sd-ui|open-webui|haproxy|homeassistant|promtail|prometheus|grafana|loki|enigma_nginx_1).*'
        action: keep
```

Add the new container names to the alternation:

```yaml
        regex: '/(rknn-lcm-sd-ui|open-webui|haproxy|homeassistant|promtail|prometheus|grafana|loki|enigma_nginx_1|yukis-wordpress|yukis-mariadb|yukis-ddns).*'
```

Restart promtail:

```bash
ssh node2.lan 'docker restart promtail'
```

- [ ] **Step 10: Verify logs are reaching Loki**

```bash
curl -sG 'http://node1.lan:3100/loki/api/v1/query' \
  --data-urlencode 'query={container="yukis-wordpress"}' | head -c 400
```

Expected: JSON containing log lines, not an empty `"result":[]`. An empty result means the allowlist edit did not take effect — recheck the regex and that you edited the file promtail actually loads.

- [ ] **Step 11: Commit**

```bash
git add deploy/wordpress/
git commit -m "feat: WordPress authoring stack for node2

Docker Compose with WordPress, MariaDB, and an in-stack Cloudflare DDNS
updater that pins the proxied flag. No host-specific bind mounts, so the
stack relocates to a VPS by moving volumes."
```

---

## Task 3: TLS termination and reverse proxy

**Files:**
- Create: `docs/superpowers/plans/notes/task-03-proxy.md` (record the DSM rule as configured)

**Interfaces:**
- Consumes: `control.yukisrescue.org` A record, proxied (Task 2); `WP_HOST_PORT` (Task 1).
- Produces: `https://control.yukisrescue.org` serving WordPress end to end.

DSM's reverse proxy and certificate store have no supported CLI, so these steps are GUI actions. They are written precisely enough to be followed without interpretation.

- [ ] **Step 1: Import the Origin CA certificate into DSM**

DSM → Control Panel → Security → Certificate → Add → Add a new certificate → Import certificate.

- Private Key: `~/workspace/yukis/yukis_pk.pem`
- Certificate: `~/workspace/yukis/yukis.origin.cert.pem`
- Intermediate certificate: leave empty
- Description: `Cloudflare Origin CA *.yukisrescue.org (exp 2041-02-27)`

- [ ] **Step 2: Create the reverse proxy rule**

DSM → Control Panel → Login Portal → Advanced → Reverse Proxy → Create.

| Field | Value |
|---|---|
| Description | `yukis control (WordPress)` |
| Source protocol | HTTPS |
| Source hostname | `control.yukisrescue.org` |
| Source port | 443 |
| Enable HSTS | off |
| Destination protocol | HTTP |
| Destination hostname | `node2.lan` |
| Destination port | `8080` |

Under Custom Header → Create → **WebSocket** (adds `Upgrade` and `Connection`). Then add these headers manually — WordPress behind a TLS terminator needs them or it will redirect-loop:

| Header | Value |
|---|---|
| `X-Forwarded-Proto` | `https` |
| `X-Forwarded-For` | `$proxy_add_x_forwarded_for` |
| `X-Real-IP` | `$remote_addr` |
| `Host` | `$host` |

- [ ] **Step 3: Bind the certificate to the rule**

DSM → Control Panel → Security → Certificate → Settings. Set the service `control.yukisrescue.org` to use the imported Cloudflare Origin CA certificate. Apply.

- [ ] **Step 4: Set Cloudflare SSL mode to Full (strict)**

Cloudflare dashboard → `yukisrescue.org` → SSL/TLS → Overview → **Full (strict)**.

Full (strict) is required. `Flexible` would leave the origin leg unencrypted; plain `Full` would accept any certificate and defeat the point of the Origin CA.

- [ ] **Step 5: Verify TLS terminates correctly**

```bash
curl -sSI https://control.yukisrescue.org/wp-admin/install.php | head -3
```

Expected: `HTTP/2 200`. 

Diagnosis if it fails:
- `525` / `526` — origin TLS handshake failed. The certificate is not bound to the rule (Step 3), or SSL mode is Full (strict) while DSM is serving a different certificate.
- `522` — Cloudflare cannot reach the Synology. Check port 443 forwarding and that the DNS record points at the current WAN IP.
- Redirect loop — the `X-Forwarded-Proto` header from Step 2 is missing, or the `$$` escaping in Task 2 Step 1 was wrong.

- [ ] **Step 6: Verify the origin is not directly reachable**

```bash
curl -sS --max-time 10 -o /dev/null -w "%{http_code}\n" --resolve control.yukisrescue.org:443:$(curl -s ifconfig.me) https://control.yukisrescue.org/ || echo "direct connection refused or untrusted — correct"
```

Expected: a certificate error or refusal. A clean `200` means traffic is bypassing Cloudflare, which would expose wp-admin directly to the internet.

- [ ] **Step 7: Record and commit**

Write the exact rule and header set into `docs/superpowers/plans/notes/task-03-proxy.md`, so the configuration can be rebuilt after a DSM reset.

```bash
git add docs/superpowers/plans/notes/task-03-proxy.md
git commit -m "docs: record DSM reverse proxy and TLS configuration"
```

---

## Task 4: Cloudflare Access in front of wp-admin

Until this task is complete, `wp-login.php` is publicly reachable. Do not create user accounts or install plugins before it lands.

**Files:**
- Create: `docs/superpowers/plans/notes/task-04-access.md`

**Interfaces:**
- Consumes: `https://control.yukisrescue.org` (Task 3); designer addresses from `~/workspace/yukis/designer_emails.yml` (keys `holly`, `jen`, `louis`).
- Produces: unauthenticated requests to `control.yukisrescue.org` receive an Access challenge.

Configured by hand in the dashboard. The deploy tokens deliberately hold no Access permissions — a token that can rewrite the policy protecting wp-admin undermines the control it configures.

- [ ] **Step 1: Enable Zero Trust**

Cloudflare dashboard → Zero Trust. If prompted, choose a team name and the **Free** plan (50 users).

- [ ] **Step 2: Create the Access application**

Zero Trust → Access → Applications → Add an application → **Self-hosted**.

| Field | Value |
|---|---|
| Application name | `Yuki's Rescue WordPress` |
| Session duration | 24 hours |
| Subdomain | `control` |
| Domain | `yukisrescue.org` |
| Path | *(leave empty — protects the whole host)* |

- [ ] **Step 3: Add the access policy**

Add policy:

| Field | Value |
|---|---|
| Policy name | `Designers and owner` |
| Action | Allow |
| Rule type | Include → **Emails** |

Enter the four addresses: the three from `designer_emails.yml` plus the owner's. Read them from the file; do not retype from memory.

- [ ] **Step 4: Confirm the login method is enabled**

Zero Trust → Settings → Authentication. Ensure **One-time PIN** is enabled. It requires no identity-provider setup and works with the Gmail and iCloud addresses on the list.

- [ ] **Step 5: Verify unauthenticated requests are challenged**

```bash
curl -sSI https://control.yukisrescue.org/wp-login.php | head -5
```

Expected: `HTTP/2 302` with a `location:` header pointing at `cloudflareaccess.com`. 

A `200` means the application is not matching — recheck the subdomain and domain fields in Step 2.

- [ ] **Step 6: Verify a human can actually get in**

In a browser, visit `https://control.yukisrescue.org/wp-admin/install.php`. Expected: Cloudflare's one-time PIN prompt, then the WordPress installer after entering the emailed code.

Do this before onboarding designers. A locked-out designer on day one is an avoidable bad first impression.

- [ ] **Step 7: Record and commit**

```bash
git add docs/superpowers/plans/notes/task-04-access.md
git commit -m "docs: record Cloudflare Access configuration for wp-admin"
```

---

## Task 5: WordPress installation and hardening

**Files:**
- Create: `deploy/wordpress/wp-setup.sh`

**Interfaces:**
- Consumes: Access-protected WordPress (Task 4).
- Produces: an installed site, one Administrator, three Editor accounts, pretty permalinks enabled.

- [ ] **Step 1: Write the setup script**

Create `deploy/wordpress/wp-setup.sh`. It is idempotent so it can be re-run safely:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Runs WP-CLI inside the WordPress container.
wp() { docker exec -u www-data yukis-wordpress wp "$@"; }

: "${ADMIN_USER:?set ADMIN_USER}"
: "${ADMIN_EMAIL:?set ADMIN_EMAIL}"
: "${ADMIN_PASSWORD:?set ADMIN_PASSWORD}"
: "${SITE_URL:?set SITE_URL}"

if ! wp core is-installed 2>/dev/null; then
  wp core install \
    --url="$SITE_URL" \
    --title="Yuki's Rescue" \
    --admin_user="$ADMIN_USER" \
    --admin_email="$ADMIN_EMAIL" \
    --admin_password="$ADMIN_PASSWORD" \
    --skip-email
  echo "installed"
else
  echo "already installed"
fi

# Pretty permalinks. Must be set before content exists or URLs churn later.
wp rewrite structure '/%postname%/' --hard

# Remove default content that would otherwise be exported to production.
wp post delete "$(wp post list --post_type=post --format=ids)" --force 2>/dev/null || true
wp post delete "$(wp post list --post_type=page --name=sample-page --format=ids)" --force 2>/dev/null || true
wp plugin delete akismet hello 2>/dev/null || true

# Discourage indexing of the authoring host.
wp option update blog_public 0

echo "setup complete"
```

```bash
chmod +x deploy/wordpress/wp-setup.sh
```

`blog_public 0` matters: without it, `control.yukisrescue.org` can be indexed and compete with production in search results. The static export ignores this setting, so production indexing is unaffected.

- [ ] **Step 2: Verify WP-CLI is available in the image**

```bash
ssh node2.lan 'docker exec -u www-data yukis-wordpress wp --info' || echo "WP-CLI ABSENT"
```

Expected: version output. If it prints `WP-CLI ABSENT`, install it into the container and record the change:

```bash
ssh node2.lan 'docker exec yukis-wordpress bash -c "curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && chmod +x wp-cli.phar && mv wp-cli.phar /usr/local/bin/wp"'
```

This is lost on image update. If it is needed, add a note to Task 2's compose file to bake it in via a small `Dockerfile`.

- [ ] **Step 3: Run setup**

```bash
rsync -av deploy/wordpress/wp-setup.sh node2.lan:/opt/wordpress/
ssh -t node2.lan 'cd /opt/wordpress && read -s -p "admin password: " ADMIN_PASSWORD && export ADMIN_PASSWORD && \
  ADMIN_USER=<owner-username> ADMIN_EMAIL=<owner-email> SITE_URL=https://control.yukisrescue.org ./wp-setup.sh'
```

- [ ] **Step 4: Verify installation state**

```bash
ssh node2.lan 'docker exec -u www-data yukis-wordpress wp option get permalink_structure; \
  docker exec -u www-data yukis-wordpress wp option get blog_public; \
  docker exec -u www-data yukis-wordpress wp post list --post_type=page --format=count'
```

Expected: `/%postname%/`, then `0`, then `0`.

- [ ] **Step 5: Create the three designer accounts**

```bash
ssh node2.lan 'docker exec -u www-data yukis-wordpress wp user create holly <holly-email> --role=editor --send-email=false'
```

Repeat for `jen` and `louis`, reading each address from `~/workspace/yukis/designer_emails.yml`.

- [ ] **Step 6: Verify roles are Editor, not Administrator**

```bash
ssh node2.lan 'docker exec -u www-data yukis-wordpress wp user list --fields=user_login,roles'
```

Expected: exactly one `administrator`; `holly`, `jen`, and `louis` each `editor`. An extra administrator is a finding, not a detail — Editors cannot install plugins or execute code, and that is the containment boundary.

- [ ] **Step 7: Install and configure two-factor authentication**

```bash
ssh node2.lan 'docker exec -u www-data yukis-wordpress wp plugin install two-factor --activate'
```

Then enrol the Administrator account through the browser at Users → Profile → Two-Factor Options.

- [ ] **Step 8: Commit**

```bash
git add deploy/wordpress/wp-setup.sh
git commit -m "feat: WordPress install and hardening script

Idempotent setup: pretty permalinks before content exists, default content
removed so it cannot reach production, authoring host de-indexed, designers
provisioned as Editors."
```

---

## Task 6: Block theme carrying the current design

**Files:**
- Create: `theme/yukis/style.css`
- Create: `theme/yukis/theme.json`
- Create: `theme/yukis/templates/index.html`
- Create: `theme/yukis/templates/page.html`
- Create: `theme/yukis/parts/header.html`
- Create: `theme/yukis/parts/footer.html`
- Create: `theme/yukis/patterns/org-footer.php`
- Reference: `index.html` (current design, source of the token values)

**Interfaces:**
- Produces: an active theme named `yukis`, exposing the palette as Site Editor swatches with slugs `primary`, `secondary`, `surface`, `footer`, `body-text`.

The purpose of this task is to convert five duplicated inline `<style>` blocks into design tokens. The rendered appearance should not change; what changes is that designers can edit it.

- [ ] **Step 1: Write the theme stylesheet header**

Create `theme/yukis/style.css`:

```css
/*
Theme Name: Yuki's Rescue
Theme URI: https://www.yukisrescue.org
Author: Yuki's Rescue
Description: Block theme for Yuki's Rescue. Design tokens live in theme.json.
Version: 1.0.0
Requires at least: 6.4
Tested up to: 6.7
Requires PHP: 8.0
License: GPL-2.0-or-later
Text Domain: yukis
*/
```

- [ ] **Step 2: Write `theme.json` with the current design's tokens**

Create `theme/yukis/theme.json`:

```json
{
  "$schema": "https://schemas.wp.org/trunk/theme.json",
  "version": 3,
  "settings": {
    "appearanceTools": true,
    "layout": { "contentSize": "1200px", "wideSize": "1200px" },
    "color": {
      "defaultPalette": false,
      "defaultGradients": false,
      "palette": [
        { "slug": "primary",    "color": "#667eea", "name": "Primary" },
        { "slug": "secondary",  "color": "#764ba2", "name": "Secondary" },
        { "slug": "surface",    "color": "#f8f9fa", "name": "Card Surface" },
        { "slug": "footer",     "color": "#2d3748", "name": "Footer" },
        { "slug": "body-text",  "color": "#333333", "name": "Body Text" },
        { "slug": "white",      "color": "#ffffff", "name": "White" }
      ],
      "gradients": [
        {
          "slug": "brand",
          "name": "Brand",
          "gradient": "linear-gradient(135deg, #667eea 0%, #764ba2 100%)"
        }
      ]
    },
    "typography": {
      "fontFamilies": [
        {
          "slug": "system",
          "name": "System",
          "fontFamily": "'Segoe UI', Tahoma, Geneva, Verdana, sans-serif"
        }
      ]
    },
    "spacing": { "units": ["px", "rem", "%", "vh"] }
  },
  "styles": {
    "color": { "text": "var(--wp--preset--color--body-text)" },
    "typography": {
      "fontFamily": "var(--wp--preset--font-family--system)",
      "lineHeight": "1.6"
    },
    "elements": {
      "button": {
        "color": {
          "background": "var(--wp--preset--color--primary)",
          "text": "var(--wp--preset--color--white)"
        },
        "border": { "radius": "50px" },
        "spacing": { "padding": { "top": "1rem", "bottom": "1rem", "left": "2rem", "right": "2rem" } },
        "typography": { "fontWeight": "700" }
      },
      "h2": {
        "color": { "text": "var(--wp--preset--color--primary)" },
        "typography": { "fontSize": "2.5rem" }
      }
    }
  },
  "templateParts": [
    { "name": "header", "title": "Header", "area": "header" },
    { "name": "footer", "title": "Footer", "area": "footer" }
  ]
}
```

Every value here is copied from the current `index.html`. Do not "improve" them — matching the existing site is the acceptance criterion.

- [ ] **Step 3: Write the header template part**

Create `theme/yukis/parts/header.html`:

```html
<!-- wp:group {"style":{"spacing":{"padding":{"top":"1rem","bottom":"1rem"}}},"gradient":"brand","layout":{"type":"constrained"}} -->
<div class="wp-block-group has-brand-gradient-background has-background" style="padding-top:1rem;padding-bottom:1rem">
  <!-- wp:group {"layout":{"type":"flex","justifyContent":"space-between"}} -->
  <div class="wp-block-group">
    <!-- wp:site-title {"style":{"typography":{"fontSize":"1.8rem","fontWeight":"700"}},"textColor":"white"} /-->
    <!-- wp:navigation {"textColor":"white","layout":{"type":"flex","justifyContent":"right"}} /-->
  </div>
  <!-- /wp:group -->
</div>
<!-- /wp:group -->
```

- [ ] **Step 4: Write the footer template part and the organization pattern**

Create `theme/yukis/parts/footer.html`:

```html
<!-- wp:group {"backgroundColor":"footer","textColor":"white","style":{"spacing":{"padding":{"top":"2rem","bottom":"2rem"}}},"layout":{"type":"constrained"}} -->
<div class="wp-block-group has-white-color has-footer-background-color has-text-color has-background" style="padding-top:2rem;padding-bottom:2rem">
  <!-- wp:pattern {"slug":"yukis/org-footer"} /-->
</div>
<!-- /wp:group -->
```

Create `theme/yukis/patterns/org-footer.php` with the confirmed organization details:

```php
<?php
/**
 * Title: Organization Footer
 * Slug: yukis/org-footer
 * Categories: footer
 */
?>
<!-- wp:paragraph {"align":"center"} -->
<p class="has-text-align-center">Yuki's Rescue &mdash; 1221 Coral Reef Place, Alameda, CA</p>
<!-- /wp:paragraph -->
<!-- wp:paragraph {"align":"center"} -->
<p class="has-text-align-center"><a href="tel:+15103506924">510.350.6924</a> &middot; <a href="mailto:hello@yukisrescue.org">hello@yukisrescue.org</a></p>
<!-- /wp:paragraph -->
<!-- wp:paragraph {"align":"center","fontSize":"small"} -->
<p class="has-text-align-center has-small-font-size">A registered 501(c)(3) nonprofit organization &middot; EIN 41-4413466</p>
<!-- /wp:paragraph -->
<!-- wp:paragraph {"align":"center","fontSize":"small"} -->
<p class="has-text-align-center has-small-font-size">&copy; 2026 Yuki's Rescue. All rights reserved.</p>
<!-- /wp:paragraph -->
```

Editing this one pattern updates the footer on every page.

- [ ] **Step 5: Write the page templates**

Create `theme/yukis/templates/page.html`:

```html
<!-- wp:template-part {"slug":"header","tagName":"header"} /-->
<!-- wp:group {"style":{"spacing":{"padding":{"top":"4rem","bottom":"4rem","left":"2rem","right":"2rem"}}},"layout":{"type":"constrained"}} -->
<div class="wp-block-group" style="padding-top:4rem;padding-right:2rem;padding-bottom:4rem;padding-left:2rem">
  <!-- wp:post-title {"level":1,"textColor":"primary"} /-->
  <!-- wp:post-content {"layout":{"type":"constrained"}} /-->
</div>
<!-- /wp:group -->
<!-- wp:template-part {"slug":"footer","tagName":"footer"} /-->
```

Create `theme/yukis/templates/index.html` with identical content — it is the required fallback template.

- [ ] **Step 6: Install and activate the theme**

```bash
rsync -av theme/yukis/ node2.lan:/tmp/yukis-theme/
ssh node2.lan 'docker cp /tmp/yukis-theme yukis-wordpress:/var/www/html/wp-content/themes/yukis && \
  docker exec yukis-wordpress chown -R www-data:www-data /var/www/html/wp-content/themes/yukis && \
  docker exec -u www-data yukis-wordpress wp theme activate yukis'
```

- [ ] **Step 7: Verify the theme is active and the palette registered**

```bash
ssh node2.lan 'docker exec -u www-data yukis-wordpress wp theme list --status=active --field=name; \
  docker exec -u www-data yukis-wordpress wp eval "\$d = WP_Theme_JSON_Resolver::get_merged_data()->get_settings(); foreach (\$d[\"color\"][\"palette\"][\"theme\"] as \$c) { echo \$c[\"slug\"], \"=\", \$c[\"color\"], PHP_EOL; }"'
```

Expected: `yukis`, then the six palette entries with the exact hex values from Step 2. If the palette is empty, `theme.json` failed to parse — validate it as JSON.

- [ ] **Step 8: Verify the design survives a round trip in the browser**

Open `https://control.yukisrescue.org/wp-admin/site-editor.php`. Confirm the colour picker shows the six named swatches and the Brand gradient. This is the deliverable — designers editing colours without touching code.

- [ ] **Step 9: Commit**

```bash
git add theme/yukis/
git commit -m "feat: block theme with current design as theme.json tokens

Converts five duplicated inline style blocks into a single token set.
Rendered appearance is unchanged; the design is now editable from the
Site Editor without code."
```

---

## Task 7: Migrate content into WordPress

**Files:**
- Create: `deploy/wordpress/wp-content-seed.sh`
- Modify: repository root — move `about.html`, `feedback.html`, `index.html`, `rescue.html`, `styles.css` into `legacy/`
- Delete: `styles.css` reference (orphaned dark theme, referenced by no page)

**Interfaces:**
- Consumes: active `yukis` theme (Task 6).
- Produces: four published pages — `/` (front), `/about/`, `/rescue/`, `/feedback/` — plus a navigation menu and the hero image in the media library.

- [ ] **Step 1: Write the content seeding script**

Create `deploy/wordpress/wp-content-seed.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
wp() { docker exec -u www-data yukis-wordpress wp "$@"; }

page_id() { wp post list --post_type=page --name="$1" --field=ID | head -1; }

create_page() {
  local slug="$1" title="$2" content="$3"
  local existing; existing="$(page_id "$slug")"
  if [ -n "$existing" ]; then
    wp post update "$existing" --post_title="$title" --post_content="$content"
    echo "updated $slug"
  else
    wp post create --post_type=page --post_status=publish \
      --post_name="$slug" --post_title="$title" --post_content="$content"
    echo "created $slug"
  fi
}

PLACEHOLDER='<!-- wp:group {"backgroundColor":"surface","style":{"spacing":{"padding":{"top":"3rem","bottom":"3rem","left":"3rem","right":"3rem"}},"border":{"radius":"10px","width":"2px","style":"dashed","color":"#667eea"}},"layout":{"type":"constrained"}} -->
<div class="wp-block-group has-border-color has-surface-background-color has-background" style="border-color:#667eea;border-style:dashed;border-width:2px;border-radius:10px;padding:3rem"><!-- wp:paragraph {"align":"center"} -->
<p class="has-text-align-center">This page is currently under construction.</p>
<!-- /wp:paragraph --><!-- wp:paragraph {"align":"center"} -->
<p class="has-text-align-center">Please check back soon for updates!</p>
<!-- /wp:paragraph --></div>
<!-- /wp:group -->'

create_page about    "About Us"      "$PLACEHOLDER"
create_page rescue   "Rescue a Dog"  "$PLACEHOLDER"
create_page feedback "Feedback"      "$PLACEHOLDER"

HOME_CONTENT="$(cat /opt/wordpress/seed/home.html)"
create_page home "Saving Lives, One Paw at a Time" "$HOME_CONTENT"

HOME_ID="$(page_id home)"
wp option update show_on_front page
wp option update page_on_front "$HOME_ID"

echo "content seed complete"
```

```bash
chmod +x deploy/wordpress/wp-content-seed.sh
```

- [ ] **Step 2: Write the homepage block content**

Create `deploy/wordpress/seed/home.html`. Port the mission text, the four value cards, and the CTA from the current `index.html` verbatim — the copy is approved and must not be rewritten:

```html
<!-- wp:cover {"url":"HERO_URL","dimRatio":40,"minHeight":400,"align":"full"} -->
<div class="wp-block-cover alignfull"><span aria-hidden="true" class="wp-block-cover__background has-background-dim-40 has-background-dim"></span><img class="wp-block-cover__image-background" src="HERO_URL" alt=""/><div class="wp-block-cover__inner-container"><!-- wp:heading {"textAlign":"center","level":1,"textColor":"white"} -->
<h1 class="wp-block-heading has-text-align-center has-white-color has-text-color">Saving Lives, One Paw at a Time</h1>
<!-- /wp:heading --><!-- wp:paragraph {"align":"center","textColor":"white"} -->
<p class="has-text-align-center has-white-color has-text-color">Every dog deserves a second chance at happiness</p>
<!-- /wp:paragraph --><!-- wp:buttons {"layout":{"type":"flex","justifyContent":"center"}} -->
<div class="wp-block-buttons"><!-- wp:button -->
<div class="wp-block-button"><a class="wp-block-button__link wp-element-button" href="/rescue/">Rescue a Dog Today</a></div>
<!-- /wp:button --></div>
<!-- /wp:buttons --></div></div>
<!-- /wp:cover -->

<!-- wp:heading {"textAlign":"center","textColor":"primary"} -->
<h2 class="wp-block-heading has-text-align-center has-primary-color has-text-color">Our Mission</h2>
<!-- /wp:heading -->

<!-- wp:paragraph {"align":"center"} -->
<p class="has-text-align-center">At Yuki's Rescue, we are dedicated to rescuing, rehabilitating, and rehoming dogs in need. We believe that every animal deserves compassion, care, and a loving forever home. Through our network of dedicated volunteers and foster families, we work tirelessly to give abandoned and neglected dogs a second chance at life.</p>
<!-- /wp:paragraph -->

<!-- wp:heading {"textAlign":"center","textColor":"primary"} -->
<h2 class="wp-block-heading has-text-align-center has-primary-color has-text-color">Our Values</h2>
<!-- /wp:heading -->

<!-- wp:columns -->
<div class="wp-block-columns"><!-- wp:column {"backgroundColor":"surface","style":{"border":{"radius":"10px"},"spacing":{"padding":{"top":"2rem","bottom":"2rem","left":"2rem","right":"2rem"}}}} -->
<div class="wp-block-column has-surface-background-color has-background" style="border-radius:10px;padding:2rem"><!-- wp:heading {"level":3,"textColor":"primary"} -->
<h3 class="wp-block-heading has-primary-color has-text-color">🐕 Compassion</h3>
<!-- /wp:heading --><!-- wp:paragraph -->
<p>We treat every animal with kindness, dignity, and respect, recognizing their inherent worth and right to a life free from suffering.</p>
<!-- /wp:paragraph --></div>
<!-- /wp:column -->
<!-- wp:column {"backgroundColor":"surface","style":{"border":{"radius":"10px"},"spacing":{"padding":{"top":"2rem","bottom":"2rem","left":"2rem","right":"2rem"}}}} -->
<div class="wp-block-column has-surface-background-color has-background" style="border-radius:10px;padding:2rem"><!-- wp:heading {"level":3,"textColor":"primary"} -->
<h3 class="wp-block-heading has-primary-color has-text-color">💝 Commitment</h3>
<!-- /wp:heading --><!-- wp:paragraph -->
<p>We are unwavering in our dedication to each animal in our care, providing medical treatment, rehabilitation, and support until they find their forever home.</p>
<!-- /wp:paragraph --></div>
<!-- /wp:column -->
<!-- wp:column {"backgroundColor":"surface","style":{"border":{"radius":"10px"},"spacing":{"padding":{"top":"2rem","bottom":"2rem","left":"2rem","right":"2rem"}}}} -->
<div class="wp-block-column has-surface-background-color has-background" style="border-radius:10px;padding:2rem"><!-- wp:heading {"level":3,"textColor":"primary"} -->
<h3 class="wp-block-heading has-primary-color has-text-color">🤝 Community</h3>
<!-- /wp:heading --><!-- wp:paragraph -->
<p>We believe in the power of community and work collaboratively with volunteers, fosters, donors, and partners to achieve our mission.</p>
<!-- /wp:paragraph --></div>
<!-- /wp:column -->
<!-- wp:column {"backgroundColor":"surface","style":{"border":{"radius":"10px"},"spacing":{"padding":{"top":"2rem","bottom":"2rem","left":"2rem","right":"2rem"}}}} -->
<div class="wp-block-column has-surface-background-color has-background" style="border-radius:10px;padding:2rem"><!-- wp:heading {"level":3,"textColor":"primary"} -->
<h3 class="wp-block-heading has-primary-color has-text-color">✨ Integrity</h3>
<!-- /wp:heading --><!-- wp:paragraph -->
<p>We operate with transparency, honesty, and accountability in all our operations, ensuring that resources are used effectively to save lives.</p>
<!-- /wp:paragraph --></div>
<!-- /wp:column --></div>
<!-- /wp:columns -->

<!-- wp:group {"gradient":"brand","textColor":"white","style":{"border":{"radius":"10px"},"spacing":{"padding":{"top":"4rem","bottom":"4rem","left":"2rem","right":"2rem"}}},"layout":{"type":"constrained"}} -->
<div class="wp-block-group has-white-color has-brand-gradient-background has-text-color has-background" style="border-radius:10px;padding:4rem 2rem"><!-- wp:heading {"textAlign":"center","textColor":"white"} -->
<h2 class="wp-block-heading has-text-align-center has-white-color has-text-color">Ready to Make a Difference?</h2>
<!-- /wp:heading --><!-- wp:paragraph {"align":"center"} -->
<p class="has-text-align-center">Whether you're looking to adopt, volunteer, or donate, there are many ways to help us save more lives.</p>
<!-- /wp:paragraph --><!-- wp:buttons {"layout":{"type":"flex","justifyContent":"center"}} -->
<div class="wp-block-buttons"><!-- wp:button -->
<div class="wp-block-button"><a class="wp-block-button__link wp-element-button" href="/rescue/">Get Involved</a></div>
<!-- /wp:button --></div>
<!-- /wp:buttons --></div>
<!-- /wp:group -->
```

- [ ] **Step 3: Compress and import the hero image**

The committed `hero_banner.jpg` is 1.5MB for a background image. Compress it first:

```bash
sips -Z 2000 hero_banner.jpg --out /tmp/hero_banner.jpg
sips -s format jpeg -s formatOptions 72 /tmp/hero_banner.jpg --out /tmp/hero_banner_opt.jpg
ls -lh /tmp/hero_banner_opt.jpg
```

Expected: under 300KB. Then import and capture the resulting URL:

```bash
scp /tmp/hero_banner_opt.jpg node2.lan:/tmp/hero_banner.jpg
ssh node2.lan 'docker cp /tmp/hero_banner.jpg yukis-wordpress:/tmp/ && \
  docker exec -u www-data yukis-wordpress wp media import /tmp/hero_banner.jpg --title="Hero Banner" --porcelain'
```

Record the attachment ID, then resolve its URL:

```bash
ssh node2.lan 'docker exec -u www-data yukis-wordpress wp post get <ID> --field=guid'
```

Substitute that URL for `HERO_URL` in `seed/home.html` before running the seed script.

- [ ] **Step 4: Run the content seed**

```bash
rsync -av deploy/wordpress/wp-content-seed.sh deploy/wordpress/seed/ node2.lan:/opt/wordpress/
ssh node2.lan 'cd /opt/wordpress && ./wp-content-seed.sh'
```

- [ ] **Step 5: Build the navigation menu**

```bash
ssh node2.lan 'docker exec -u www-data yukis-wordpress wp menu create "Primary"; \
  docker exec -u www-data yukis-wordpress wp menu item add-post primary $(docker exec -u www-data yukis-wordpress wp post list --post_type=page --name=about --field=ID); \
  docker exec -u www-data yukis-wordpress wp menu item add-post primary $(docker exec -u www-data yukis-wordpress wp post list --post_type=page --name=rescue --field=ID); \
  docker exec -u www-data yukis-wordpress wp menu item add-post primary $(docker exec -u www-data yukis-wordpress wp post list --post_type=page --name=feedback --field=ID); \
  docker exec -u www-data yukis-wordpress wp menu item add-custom primary "Contact" "mailto:hello@yukisrescue.org"'
```

- [ ] **Step 6: Verify all four pages render**

```bash
for p in "" about rescue feedback; do
  printf "%-10s " "/$p"
  curl -sS -o /dev/null -w "%{http_code}\n" "https://control.yukisrescue.org/$p/" \
    -H "CF-Access-Client-Id: $CF_SERVICE_ID" -H "CF-Access-Client-Secret: $CF_SERVICE_SECRET" 2>/dev/null \
    || echo "(behind Access — verify in browser)"
done
```

Because Access protects the host, verify in a browser instead: each of `/`, `/about/`, `/rescue/`, `/feedback/` returns the page with header, content, and the organization footer.

- [ ] **Step 7: Move the superseded static files out of the deploy root**

WordPress is now the source of truth. Leaving hand-written HTML at the repository root creates two sources of truth and it is currently the deploy directory.

```bash
mkdir -p legacy
git mv index.html about.html rescue.html feedback.html styles.css legacy/
git mv hero_banner.jpg legacy/
```

`styles.css` is the orphaned dark theme referenced by no page; it moves to `legacy/` rather than being deleted, so the history stays browsable.

- [ ] **Step 8: Commit**

```bash
git add deploy/wordpress/wp-content-seed.sh deploy/wordpress/seed/ legacy/
git commit -m "feat: seed WordPress with current site content

Four pages reproducing the existing site, hero image compressed from 1.5MB,
nav menu, front page set. Hand-written HTML moved to legacy/ so WordPress is
the single source of truth."
```

---

## Task 8: Characterize Simply Static's export

The next two tasks depend on facts about this plugin's free tier that must be measured, not assumed. Do not skip ahead — a pipeline built on a guessed output path fails in a way that looks like a git problem.

**Files:**
- Create: `docs/superpowers/plans/notes/task-08-simply-static.md`

**Interfaces:**
- Produces: recorded values for the export output path inside the container, whether the free tier exposes a WP-CLI command, and which URL mode produces portable links.

- [ ] **Step 1: Install the plugin**

```bash
ssh node2.lan 'docker exec -u www-data yukis-wordpress wp plugin install simply-static --activate'
```

- [ ] **Step 2: Determine whether a WP-CLI command exists**

```bash
ssh node2.lan 'docker exec -u www-data yukis-wordpress wp help simply-static 2>&1 | head -20'
```

Record the answer. If a CLI command exists, Task 10 becomes substantially simpler — the watcher can be replaced by a direct invocation. If it does not, the file-watcher approach in Task 10 stands.

- [ ] **Step 3: Configure the export for portable URLs**

In the browser at Settings → Simply Static:

| Setting | Value | Reason |
|---|---|---|
| Destination URLs | **Use relative URLs** | The export is generated on `control.` but served on `www.` Relative URLs work on both; absolute URLs would bake in the wrong hostname. |
| Delivery Method | **Local Directory** | |
| Local Directory | `/var/www/html/wp-content/uploads/simply-static/out/` | Inside the `wp_export` volume from Task 2 |
| Additional URLs | `https://control.yukisrescue.org/wp-sitemap.xml` | Guarantees pages linked from nowhere are still exported |

- [ ] **Step 4: Run an export and record what it produces**

Click Generate Static Files. When it completes:

```bash
ssh node2.lan 'docker exec yukis-wordpress find /var/www/html/wp-content/uploads/simply-static -maxdepth 3 -type d | head -20; \
  echo "--- files ---"; \
  docker exec yukis-wordpress find /var/www/html/wp-content/uploads/simply-static/out -type f | head -40'
```

Expected: `index.html`, `about/index.html`, `rescue/index.html`, `feedback/index.html`, plus `wp-includes/` and `wp-content/` assets.

- [ ] **Step 5: Verify the exported links are relative**

```bash
ssh node2.lan 'docker exec yukis-wordpress grep -o "href=\"[^\"]*\"" /var/www/html/wp-content/uploads/simply-static/out/index.html | head -20'
```

Expected: paths like `href="/about/"`. 

**If you see `href="https://control.yukisrescue.org/about/"`, stop.** The export is unusable — production would link back to the authoring host, which is behind Access and would lock visitors out. Recheck Step 3.

- [ ] **Step 6: Confirm the export completes without the placeholder pages breaking**

```bash
ssh node2.lan 'docker exec yukis-wordpress grep -l "under construction" /var/www/html/wp-content/uploads/simply-static/out/*/index.html'
```

Expected: three matches (`about`, `rescue`, `feedback`).

- [ ] **Step 7: Record findings and commit**

Write into `docs/superpowers/plans/notes/task-08-simply-static.md`: the exact output path, whether WP-CLI is available, how completion is detectable (a marker file, a timestamp, a log line), and the observed file count.

```bash
git add docs/superpowers/plans/notes/task-08-simply-static.md
git commit -m "docs: record Simply Static export behaviour on the free tier"
```

---

## Task 9: Publish script

**Files:**
- Create: `deploy/wordpress/publish.sh`
- Create: `deploy/wordpress/tests/test-publish.sh`

**Interfaces:**
- Consumes: export path from Task 8; the GitHub PAT (`yukisrescue`, `admin: true`).
- Produces: a script that syncs the export into a clone of this repository under `site/`, commits, and pushes — triggering Task 11's workflow.

- [ ] **Step 1: Write the failing test first**

Create `deploy/wordpress/tests/test-publish.sh`:

```bash
#!/usr/bin/env bash
# Tests publish.sh against fixtures. No network, no real git remote.
set -uo pipefail
FAILURES=0
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

assert() {
  if [ "$2" = "$3" ]; then echo "  PASS $1"; else
    echo "  FAIL $1: expected '$3', got '$2'"; FAILURES=$((FAILURES+1)); fi
}

setup() {
  WORK="$(mktemp -d)"
  export EXPORT_DIR="$WORK/export" REPO_DIR="$WORK/repo"
  mkdir -p "$EXPORT_DIR" "$REPO_DIR"
  ( cd "$REPO_DIR" && git init -q && git config user.email t@t && git config user.name t \
    && mkdir -p site && echo old > site/index.html && git add -A && git commit -qm init )
}
teardown() { rm -rf "$WORK"; }

echo "test: refuses to publish an empty export"
setup
OUT="$("$HERE/../publish.sh" 2>&1)"; RC=$?
assert "exit code is 1" "$RC" "1"
assert "explains why" "$(echo "$OUT" | grep -c 'empty')" "1"
teardown

echo "test: refuses an export missing index.html"
setup
echo x > "$EXPORT_DIR/stray.txt"
OUT="$("$HERE/../publish.sh" 2>&1)"; RC=$?
assert "exit code is 1" "$RC" "1"
assert "names the missing file" "$(echo "$OUT" | grep -c 'index.html')" "1"
teardown

echo "test: publishes a valid export"
setup
echo "<html>new</html>" > "$EXPORT_DIR/index.html"
mkdir -p "$EXPORT_DIR/about" && echo "<html>about</html>" > "$EXPORT_DIR/about/index.html"
SKIP_PUSH=1 "$HERE/../publish.sh" >/dev/null 2>&1
assert "content replaced" "$(cat "$REPO_DIR/site/index.html")" "<html>new</html>"
assert "subdirectory copied" "$(cat "$REPO_DIR/site/about/index.html")" "<html>about</html>"
assert "commit created" "$(cd "$REPO_DIR" && git log --oneline | wc -l | tr -d ' ')" "2"
teardown

echo "test: removes files deleted in WordPress"
setup
( cd "$REPO_DIR" && mkdir -p site/gone && echo x > site/gone/index.html && git add -A && git commit -qm stale )
echo "<html>new</html>" > "$EXPORT_DIR/index.html"
SKIP_PUSH=1 "$HERE/../publish.sh" >/dev/null 2>&1
assert "stale path removed" "$([ -e "$REPO_DIR/site/gone" ] && echo present || echo absent)" "absent"
teardown

echo "test: no commit when nothing changed"
setup
echo old > "$EXPORT_DIR/index.html"
SKIP_PUSH=1 "$HERE/../publish.sh" >/dev/null 2>&1
assert "no empty commit" "$(cd "$REPO_DIR" && git log --oneline | wc -l | tr -d ' ')" "1"
teardown

echo
[ "$FAILURES" -eq 0 ] && echo "ALL TESTS PASSED" || { echo "$FAILURES FAILURE(S)"; exit 1; }
```

```bash
chmod +x deploy/wordpress/tests/test-publish.sh
```

- [ ] **Step 2: Run the test and watch it fail**

```bash
./deploy/wordpress/tests/test-publish.sh
```

Expected: failure — `publish.sh: No such file or directory`. Confirming the test fails for the right reason is what makes it a test rather than decoration.

- [ ] **Step 3: Write the implementation**

Create `deploy/wordpress/publish.sh`:

```bash
#!/usr/bin/env bash
# Sync a Simply Static export into the orgsite repo and push.
# Pushing triggers .github/workflows/deploy.yml, which deploys to Cloudflare.
set -euo pipefail

EXPORT_DIR="${EXPORT_DIR:?set EXPORT_DIR}"
REPO_DIR="${REPO_DIR:?set REPO_DIR}"
BRANCH="${BRANCH:-main}"

if [ -z "$(ls -A "$EXPORT_DIR" 2>/dev/null)" ]; then
  echo "ERROR: export directory is empty, refusing to publish: $EXPORT_DIR" >&2
  exit 1
fi

if [ ! -f "$EXPORT_DIR/index.html" ]; then
  echo "ERROR: export has no index.html, refusing to publish an incomplete export" >&2
  exit 1
fi

cd "$REPO_DIR"
mkdir -p site

# --delete so pages removed in WordPress disappear from production.
rsync -a --delete "$EXPORT_DIR"/ site/

if git diff --quiet && git diff --cached --quiet && [ -z "$(git status --porcelain site/)" ]; then
  echo "no changes to publish"
  exit 0
fi

git add site/
git -c user.email="wordpress@yukisrescue.org" \
    -c user.name="Yuki's Rescue WordPress" \
    commit -q -m "publish: static export $(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [ "${SKIP_PUSH:-0}" = "1" ]; then
  echo "published locally (push skipped)"
  exit 0
fi

git push origin "$BRANCH"
echo "published and pushed"
```

```bash
chmod +x deploy/wordpress/publish.sh
```

The two guard clauses exist because a failed or partial export otherwise publishes an empty `site/`, which would take production down. `rsync --delete` without them is a loaded weapon.

- [ ] **Step 4: Run the tests until they pass**

```bash
./deploy/wordpress/tests/test-publish.sh
```

Expected: `ALL TESTS PASSED`, five test groups.

- [ ] **Step 5: Commit**

```bash
git add deploy/wordpress/publish.sh deploy/wordpress/tests/test-publish.sh
git commit -m "feat: publish script syncing static export into the repo

Guards against empty and incomplete exports before rsync --delete, so a
failed export cannot blank production. Tested against fixtures."
```

---

## Task 10: Export watcher on node2

**Files:**
- Create: `deploy/wordpress/watch-export.sh`
- Create: `deploy/wordpress/systemd/yukis-publish.service`
- Create: `deploy/wordpress/systemd/yukis-publish.timer`

**Interfaces:**
- Consumes: `publish.sh` (Task 9); the export path recorded in Task 8.
- Produces: a designer clicking Generate Static Files results in a pushed commit within roughly a minute, with no terminal involved.

If Task 8 Step 2 found a working WP-CLI command, prefer driving the export directly and skip the polling design — record that decision here.

- [ ] **Step 1: Write the watcher**

Create `deploy/wordpress/watch-export.sh`:

```bash
#!/usr/bin/env bash
# Publishes when the export directory has changed and has settled.
# Runs from a systemd timer; exits immediately when there is nothing to do.
set -euo pipefail

EXPORT_DIR="${EXPORT_DIR:-/var/lib/docker/volumes/wordpress_wp_export/_data/out}"
REPO_DIR="${REPO_DIR:-/opt/wordpress/orgsite}"
STATE_FILE="${STATE_FILE:-/opt/wordpress/.last-export-hash}"
SETTLE_SECONDS="${SETTLE_SECONDS:-20}"

[ -d "$EXPORT_DIR" ] || { echo "export dir absent, nothing to do"; exit 0; }

# Newest mtime in the tree. If it changed within SETTLE_SECONDS the export is
# probably still writing, so wait for the next tick rather than publishing half.
NEWEST="$(find "$EXPORT_DIR" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1 | cut -d. -f1)"
[ -n "$NEWEST" ] || { echo "export dir empty, nothing to do"; exit 0; }

NOW="$(date +%s)"
if [ $((NOW - NEWEST)) -lt "$SETTLE_SECONDS" ]; then
  echo "export still settling, deferring"
  exit 0
fi

# Hash of paths plus mtimes: cheap and sufficient to detect a new export.
HASH="$(find "$EXPORT_DIR" -type f -printf '%p %T@\n' | sort | sha256sum | cut -d' ' -f1)"
PREV="$(cat "$STATE_FILE" 2>/dev/null || echo none)"

if [ "$HASH" = "$PREV" ]; then
  echo "no new export"
  exit 0
fi

echo "new export detected, publishing"
EXPORT_DIR="$EXPORT_DIR" REPO_DIR="$REPO_DIR" /opt/wordpress/publish.sh
echo "$HASH" > "$STATE_FILE"
```

```bash
chmod +x deploy/wordpress/watch-export.sh
```

The settle check is the important part. Simply Static writes hundreds of files over several seconds; publishing mid-write would push a half-exported site.

- [ ] **Step 2: Write the systemd units**

Create `deploy/wordpress/systemd/yukis-publish.service`:

```ini
[Unit]
Description=Publish Yuki's Rescue static export
After=docker.service

[Service]
Type=oneshot
ExecStart=/opt/wordpress/watch-export.sh
StandardOutput=journal
StandardError=journal
```

Create `deploy/wordpress/systemd/yukis-publish.timer`:

```ini
[Unit]
Description=Check for new Yuki's Rescue static exports

[Timer]
OnBootSec=2min
OnUnitActiveSec=1min
AccuracySec=10s

[Install]
WantedBy=timers.target
```

- [ ] **Step 3: Prepare the repository clone on node2**

```bash
ssh node2.lan 'cd /opt/wordpress && git clone https://github.com/yukisrescue/orgsite.git orgsite'
```

Configure credentials so the push is non-interactive. Read the PAT from `~/workspace/yukis/github_key.yml` and write it into a git credential file on node2 with mode `600`:

```bash
ssh node2.lan 'git config --global credential.helper "store --file=/opt/wordpress/.git-credentials" && \
  chmod 600 /opt/wordpress/.git-credentials 2>/dev/null || true'
```

Format of `/opt/wordpress/.git-credentials`:

```
https://yukisrescue:<PAT>@github.com
```

- [ ] **Step 4: Verify the export path resolves on the host**

The watcher reads the Docker volume from the host, so the path must be confirmed rather than assumed:

```bash
ssh node2.lan 'docker volume inspect wordpress_wp_export --format "{{.Mountpoint}}"'
ssh node2.lan 'ls "$(docker volume inspect wordpress_wp_export --format "{{.Mountpoint}}")/out" | head'
```

Expected: the mountpoint prints, and `out/` contains `index.html`. If the volume name differs (Compose prefixes it with the project directory name), correct the `EXPORT_DIR` default in Step 1.

- [ ] **Step 5: Install and start the timer**

```bash
rsync -av deploy/wordpress/ node2.lan:/opt/wordpress/ --exclude .env --exclude orgsite
ssh node2.lan 'sudo cp /opt/wordpress/systemd/yukis-publish.* /etc/systemd/system/ && \
  sudo systemctl daemon-reload && sudo systemctl enable --now yukis-publish.timer && \
  systemctl list-timers yukis-publish.timer --no-pager'
```

Expected: the timer is listed with a next elapse time.

- [ ] **Step 6: Verify a manual run publishes**

```bash
ssh node2.lan 'sudo systemctl start yukis-publish.service; sleep 5; journalctl -u yukis-publish.service -n 30 --no-pager'
```

Expected: `new export detected, publishing`, then `published and pushed`. Confirm on GitHub:

```bash
cd /Users/darkbit1001/workspace/yukis/orgsite && git fetch origin && git log origin/main --oneline -3
```

Expected: a `publish: static export ...` commit authored by `Yuki's Rescue WordPress`.

- [ ] **Step 7: Verify idempotency**

```bash
ssh node2.lan 'sudo systemctl start yukis-publish.service; sleep 3; journalctl -u yukis-publish.service -n 5 --no-pager'
```

Expected: `no new export`. A second commit here means the state file is not being written, and the pipeline would push on every tick.

- [ ] **Step 8: Commit**

```bash
git add deploy/wordpress/watch-export.sh deploy/wordpress/systemd/
git commit -m "feat: export watcher publishing on a systemd timer

Settle window prevents publishing a half-written export; a content hash in
a state file prevents republishing unchanged output every tick."
```

---

## Task 11: GitHub Actions deployment

**Files:**
- Create: `.github/workflows/deploy.yml`
- Modify: `wrangler.jsonc` — assets directory `./` → `./site`
- Modify: `.assetsignore`

**Interfaces:**
- Consumes: `site/` committed by Task 9.
- Produces: a push to `main` touching `site/**` deploys `yukis-rescue-org` to Cloudflare Workers.

- [ ] **Step 1: Point wrangler at the export directory**

Modify `wrangler.jsonc`:

```jsonc
{
  "$schema": "node_modules/wrangler/config-schema.json",
  "name": "yukis-rescue-org",
  "compatibility_date": "2026-09-01",
  "workers_dev": true,
  "assets": {
    "directory": "./site"
  },
  "routes": [
    { "pattern": "www.yukisrescue.org", "custom_domain": true }
  ]
}
```

Until this changes, `wrangler` would upload the entire repository — including `deploy/`, `docs/`, and `legacy/` — as the public site.

- [ ] **Step 2: Simplify `.assetsignore`**

With assets scoped to `site/`, most exclusions are unnecessary. Replace `.assetsignore` with:

```
.DS_Store
```

- [ ] **Step 3: Store the deploy credentials as repository secrets**

Read the `workers` token from `~/workspace/yukis/tokens.yml` and set both secrets without echoing the value:

```bash
cd /Users/darkbit1001/workspace/yukis/orgsite
export GH_TOKEN="$(tr -d '[:space:]' < ~/workspace/yukis/github_key.yml)"
gh secret set CLOUDFLARE_API_TOKEN --repo yukisrescue/orgsite < <(python3 -c "
import re
cur=None
for l in open('/Users/darkbit1001/workspace/yukis/tokens.yml'):
    m=re.match(r'^\s{2}(\w+):',l)
    if m: cur=m.group(1)
    m2=re.match(r'^\s{4}token:\s*(\S+)',l)
    if m2 and cur=='workers': print(m2.group(1),end='')
")
gh secret set CLOUDFLARE_ACCOUNT_ID --repo yukisrescue/orgsite --body "b6add582162cf7189dd6cfa6bf5f001d"
```

- [ ] **Step 4: Verify the secrets exist**

```bash
gh secret list --repo yukisrescue/orgsite
```

Expected: both `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`. Values are not readable back — that is correct.

- [ ] **Step 5: Write the workflow**

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy site

on:
  push:
    branches: [main]
    paths:
      - 'site/**'
      - 'wrangler.jsonc'
      - '.assetsignore'
      - '.github/workflows/deploy.yml'
  workflow_dispatch:

concurrency:
  group: deploy-production
  cancel-in-progress: false

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v4

      - name: Refuse to deploy an empty site
        run: |
          test -f site/index.html || { echo "site/index.html missing"; exit 1; }
          count=$(find site -type f | wc -l)
          echo "asset count: $count"
          test "$count" -ge 4 || { echo "implausibly small export, refusing"; exit 1; }

      - uses: actions/setup-node@v4
        with:
          node-version: '20'

      - run: npm ci

      - name: Upload version
        id: upload
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
        run: |
          npx wrangler versions upload 2>&1 | tee upload.log
          version_id=$(grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' upload.log | head -1)
          test -n "$version_id" || { echo "could not determine version id"; exit 1; }
          echo "version_id=$version_id" >> "$GITHUB_OUTPUT"

      - name: Deploy version to production
        env:
          CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
        run: npx wrangler versions deploy "${{ steps.upload.outputs.version_id }}@100%" --yes
```

The `concurrency` group serialises deploys — three designers publishing at once must not race. The asset-count guard is a second line of defence behind `publish.sh`'s: a workflow that would blank production fails instead.

Splitting upload from deploy is what makes the deferred preview sprint a configuration change: the preview environment gates between these two steps rather than replacing them.

- [ ] **Step 6: Commit and push, then watch the run**

```bash
git add wrangler.jsonc .assetsignore .github/workflows/deploy.yml
git commit -m "feat: deploy site/ to Cloudflare Workers via GitHub Actions

Versioned upload and deploy, serialised by a concurrency group, with an
asset-count guard that fails rather than publishing an empty site."
git push origin wordpress-authoring-pipeline
```

- [ ] **Step 7: Verify with a manual dispatch on a branch before merging**

```bash
export GH_TOKEN="$(tr -d '[:space:]' < ~/workspace/yukis/github_key.yml)"
gh workflow run deploy.yml --repo yukisrescue/orgsite --ref wordpress-authoring-pipeline
sleep 30
gh run list --workflow=deploy.yml --repo yukisrescue/orgsite --limit 1
gh run view --repo yukisrescue/orgsite --log-failed 2>/dev/null | head -40
```

Expected: `completed / success`. If the upload step fails with a permissions error, the `workers` token is missing `Workers Scripts: Edit`; if it fails attaching the route, add `Zone → DNS → Edit` as anticipated in the spec.

- [ ] **Step 8: Verify production actually served the new content**

```bash
curl -sS https://www.yukisrescue.org/ | grep -o "<title>[^<]*</title>"
curl -sS -o /dev/null -w "%{http_code}\n" https://www.yukisrescue.org/about/
```

Expected: the WordPress-generated title, and `200` for `/about/`.

---

## Task 12: End-to-end publish verification

No new files. This task proves the pipeline works from a designer's seat, which is the entire point of the project.

**Interfaces:**
- Consumes: every prior task.

- [ ] **Step 1: Make a visible content change as a designer would**

Log in to `https://control.yukisrescue.org/wp-admin/` as one of the Editor accounts — not as the Administrator. Editing the About page, replace the placeholder with a sentence of real copy. Publish.

Using an Editor account is the point: it verifies the role has sufficient permission to do the job.

- [ ] **Step 2: Trigger the export**

Settings → Simply Static → Generate Static Files. Wait for completion.

- [ ] **Step 3: Watch the change propagate**

```bash
ssh node2.lan 'journalctl -u yukis-publish.service -f --no-pager' &
sleep 90
kill %1
```

Expected: `new export detected, publishing` then `published and pushed` within about a minute of the export finishing.

- [ ] **Step 4: Confirm the commit and the deployment**

```bash
cd /Users/darkbit1001/workspace/yukis/orgsite && git fetch origin
git log origin/main --oneline -1
export GH_TOKEN="$(tr -d '[:space:]' < ~/workspace/yukis/github_key.yml)"
gh run list --workflow=deploy.yml --repo yukisrescue/orgsite --limit 1
```

Expected: a new `publish:` commit and a successful run.

- [ ] **Step 5: Confirm the change is live**

```bash
curl -sS https://www.yukisrescue.org/about/ | grep -c "under construction"
```

Expected: `0` — the placeholder is gone. Time the whole cycle and record it; designers will ask how long publishing takes.

- [ ] **Step 6: Rehearse the rollback**

This is the mitigation the security posture depends on. It must be practised before designers are handed the keys, not discovered during an incident.

```bash
cd /Users/darkbit1001/workspace/yukis/orgsite
git revert --no-edit HEAD
git push origin main
sleep 45
curl -sS https://www.yukisrescue.org/about/ | grep -c "under construction"
```

Expected: `1` — the previous content is restored. Record the elapsed time.

- [ ] **Step 7: Restore forward and document the procedure**

```bash
git revert --no-edit HEAD
git push origin main
```

Write the rollback procedure and its measured duration into `docs/superpowers/plans/notes/task-12-rollback.md`, then commit.

---

## Task 13: Backups with a tested restore

**Files:**
- Create: `deploy/wordpress/backup.sh`
- Create: `deploy/wordpress/restore.sh`
- Create: `deploy/wordpress/tests/test-backup.sh`
- Create: `deploy/wordpress/systemd/yukis-backup.service`
- Create: `deploy/wordpress/systemd/yukis-backup.timer`

**Interfaces:**
- Consumes: running stack (Task 2); writable NAS path confirmed in Task 1.
- Produces: nightly dated archives in `/media/assets/server/backup/wordpress`, and a restore path that has actually been run.

- [ ] **Step 1: Write the failing test**

Create `deploy/wordpress/tests/test-backup.sh`:

```bash
#!/usr/bin/env bash
set -uo pipefail
FAILURES=0
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

assert() {
  if [ "$2" = "$3" ]; then echo "  PASS $1"; else
    echo "  FAIL $1: expected '$3', got '$2'"; FAILURES=$((FAILURES+1)); fi
}

echo "test: fails loudly when the destination is unwritable"
DEST=/nonexistent/path OUT="$("$HERE/../backup.sh" 2>&1)"; RC=$?
assert "exit code is 1" "$RC" "1"
assert "explains why" "$(echo "$OUT" | grep -ci 'destination')" "1"

echo "test: prunes archives older than the retention window"
WORK="$(mktemp -d)"
mkdir -p "$WORK/wordpress"
touch -d '30 days ago' "$WORK/wordpress/db-20260801-000000.sql.gz"
touch -d '2 days ago'  "$WORK/wordpress/db-20260905-000000.sql.gz"
DEST="$WORK" DRY_RUN=1 "$HERE/../backup.sh" >/dev/null 2>&1
assert "old archive pruned" "$([ -e "$WORK/wordpress/db-20260801-000000.sql.gz" ] && echo present || echo absent)" "absent"
assert "recent archive kept"  "$([ -e "$WORK/wordpress/db-20260905-000000.sql.gz" ] && echo present || echo absent)" "present"
rm -rf "$WORK"

echo
[ "$FAILURES" -eq 0 ] && echo "ALL TESTS PASSED" || { echo "$FAILURES FAILURE(S)"; exit 1; }
```

```bash
chmod +x deploy/wordpress/tests/test-backup.sh
./deploy/wordpress/tests/test-backup.sh
```

Expected: failure — `backup.sh` does not exist yet.

- [ ] **Step 2: Write the backup script**

Create `deploy/wordpress/backup.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

DEST="${DEST:-/media/assets/server/backup}/wordpress"
RETAIN_DAYS="${RETAIN_DAYS:-14}"
STAMP="$(date -u +%Y%m%d-%H%M%S)"

mkdir -p "$DEST" 2>/dev/null || true
if [ ! -w "$DEST" ]; then
  echo "ERROR: backup destination is not writable: $DEST" >&2
  exit 1
fi

if [ "${DRY_RUN:-0}" != "1" ]; then
  # Database
  docker exec yukis-mariadb sh -c \
    'exec mariadb-dump --single-transaction -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"' \
    | gzip > "$DEST/db-$STAMP.sql.gz"

  # Uploads and themes
  docker run --rm \
    -v wordpress_wp_uploads:/uploads:ro \
    -v wordpress_wp_themes:/themes:ro \
    -v "$DEST":/backup \
    alpine tar czf "/backup/content-$STAMP.tar.gz" -C / uploads themes

  # Fail rather than silently writing a truncated archive.
  gzip -t "$DEST/db-$STAMP.sql.gz"
  tar tzf "$DEST/content-$STAMP.tar.gz" >/dev/null
  echo "backup complete: db-$STAMP.sql.gz content-$STAMP.tar.gz"
fi

find "$DEST" -maxdepth 1 -type f -name '*.gz' -mtime "+$RETAIN_DAYS" -delete
echo "pruned archives older than $RETAIN_DAYS days"
```

```bash
chmod +x deploy/wordpress/backup.sh
./deploy/wordpress/tests/test-backup.sh
```

Expected: `ALL TESTS PASSED`.

The integrity checks matter. A backup script that writes a corrupt archive and exits `0` is worse than none, because it removes the pressure to check.

- [ ] **Step 3: Write the restore script**

Create `deploy/wordpress/restore.sh`:

```bash
#!/usr/bin/env bash
# Restores a WordPress backup. Destructive: replaces the current database.
set -euo pipefail

DB_ARCHIVE="${1:?usage: restore.sh <db-YYYYMMDD-HHMMSS.sql.gz> <content-....tar.gz>}"
CONTENT_ARCHIVE="${2:?usage: restore.sh <db archive> <content archive>}"

[ -f "$DB_ARCHIVE" ] || { echo "missing: $DB_ARCHIVE" >&2; exit 1; }
[ -f "$CONTENT_ARCHIVE" ] || { echo "missing: $CONTENT_ARCHIVE" >&2; exit 1; }

gzip -t "$DB_ARCHIVE"
tar tzf "$CONTENT_ARCHIVE" >/dev/null

echo "This REPLACES the current WordPress database and content."
read -r -p "Type RESTORE to continue: " confirm
[ "$confirm" = "RESTORE" ] || { echo "aborted"; exit 1; }

gunzip -c "$DB_ARCHIVE" | docker exec -i yukis-mariadb sh -c \
  'exec mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE"'

docker run --rm \
  -v wordpress_wp_uploads:/uploads \
  -v wordpress_wp_themes:/themes \
  -v "$(cd "$(dirname "$CONTENT_ARCHIVE")" && pwd)":/backup:ro \
  alpine tar xzf "/backup/$(basename "$CONTENT_ARCHIVE")" -C /

docker restart yukis-wordpress
echo "restore complete"
```

```bash
chmod +x deploy/wordpress/restore.sh
```

- [ ] **Step 4: Install the nightly timer**

Create `deploy/wordpress/systemd/yukis-backup.service`:

```ini
[Unit]
Description=Back up Yuki's Rescue WordPress
After=docker.service

[Service]
Type=oneshot
ExecStart=/opt/wordpress/backup.sh
StandardOutput=journal
StandardError=journal
```

Create `deploy/wordpress/systemd/yukis-backup.timer`:

```ini
[Unit]
Description=Nightly Yuki's Rescue WordPress backup

[Timer]
OnCalendar=*-*-* 03:30:00
Persistent=true

[Install]
WantedBy=timers.target
```

```bash
rsync -av deploy/wordpress/ node2.lan:/opt/wordpress/ --exclude .env --exclude orgsite
ssh node2.lan 'sudo cp /opt/wordpress/systemd/yukis-backup.* /etc/systemd/system/ && \
  sudo systemctl daemon-reload && sudo systemctl enable --now yukis-backup.timer'
```

- [ ] **Step 5: Run a real backup and verify the archives**

```bash
ssh node2.lan 'sudo systemctl start yukis-backup.service; journalctl -u yukis-backup.service -n 20 --no-pager; \
  ls -lh /media/assets/server/backup/wordpress/'
```

Expected: `backup complete`, and two archives of plausible size. A database dump of a few kilobytes is a red flag — inspect it before trusting it.

- [ ] **Step 6: Actually exercise the restore**

The spec requires this, and it is the step most often skipped. Make a marker change, restore over it, and confirm the marker disappears.

```bash
ssh node2.lan 'docker exec -u www-data yukis-wordpress wp post create --post_type=page \
  --post_title="RESTORE TEST MARKER" --post_status=draft --porcelain'

ssh -t node2.lan 'cd /media/assets/server/backup/wordpress && \
  /opt/wordpress/restore.sh "$(ls -t db-*.sql.gz | head -1)" "$(ls -t content-*.tar.gz | head -1)"'

ssh node2.lan 'sleep 15; docker exec -u www-data yukis-wordpress wp post list --post_type=page --format=csv --fields=post_title | grep -c "RESTORE TEST MARKER" || echo 0'
```

Expected: `0`. The marker was created after the backup, so a correct restore removes it. A `1` means the restore did not take effect — do not proceed until this passes.

- [ ] **Step 7: Commit**

```bash
git add deploy/wordpress/backup.sh deploy/wordpress/restore.sh \
        deploy/wordpress/tests/test-backup.sh deploy/wordpress/systemd/yukis-backup.*
git commit -m "feat: nightly backups with a verified restore path

Archives are integrity-checked before the script reports success, and the
restore procedure has been exercised against a marker record rather than
assumed to work."
```

---

## Task 14: Contact form Worker

**Files:**
- Create: `worker-contact/src/index.js`
- Create: `worker-contact/wrangler.jsonc`
- Create: `worker-contact/package.json`
- Create: `worker-contact/test/index.test.js`
- Modify: `.github/workflows/deploy.yml` — add a job for the contact Worker

**Interfaces:**
- Consumes: Resend API key and Turnstile keys (owner-supplied, non-blocking until this task).
- Produces: `POST https://www.yukisrescue.org/api/contact` relaying to `hello@yukisrescue.org`.

Deployed as a **separate** Worker on a route, not merged into the site Worker. The site Worker is assets-only; adding a script entry point to it would complicate every content deploy for one endpoint.

- [ ] **Step 1: Add the DNS records Resend requires**

Without SPF and DKIM, relayed mail lands in spam. The `dns` token has the permission to add them.

Create the Resend account, add the domain `yukisrescue.org`, and copy the DNS records it specifies. Then add each via the API using the `dns` token, or the dashboard. Verify:

```bash
dig +short TXT resend._domainkey.yukisrescue.org
dig +short TXT send.yukisrescue.org
```

Expected: the DKIM and SPF values Resend supplied. Confirm the domain shows **Verified** in Resend before continuing.

- [ ] **Step 2: Scaffold the Worker**

Create `worker-contact/package.json`:

```json
{
  "name": "yukis-contact",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "vitest run",
    "deploy": "wrangler deploy"
  },
  "devDependencies": {
    "vitest": "^2.1.0",
    "wrangler": "^4.128.0"
  }
}
```

Create `worker-contact/wrangler.jsonc`:

```jsonc
{
  "$schema": "../node_modules/wrangler/config-schema.json",
  "name": "yukis-contact",
  "main": "src/index.js",
  "compatibility_date": "2026-09-01",
  "routes": [
    { "pattern": "www.yukisrescue.org/api/contact", "zone_name": "yukisrescue.org" }
  ]
}
```

- [ ] **Step 3: Write the failing tests**

Create `worker-contact/test/index.test.js`:

```javascript
import { describe, it, expect, vi, beforeEach } from 'vitest';
import worker from '../src/index.js';

const env = {
  RESEND_API_KEY: 'test-key',
  TURNSTILE_SECRET: 'test-secret',
  TO_EMAIL: 'hello@yukisrescue.org',
  FROM_EMAIL: 'noreply@yukisrescue.org',
};

const post = (body) =>
  new Request('https://www.yukisrescue.org/api/contact', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });

const valid = {
  name: 'Test Person',
  email: 'test@example.com',
  message: 'Hello there',
  'cf-turnstile-response': 'token',
};

beforeEach(() => { global.fetch = vi.fn(); });

describe('contact worker', () => {
  it('rejects non-POST methods', async () => {
    const res = await worker.fetch(new Request('https://www.yukisrescue.org/api/contact'), env);
    expect(res.status).toBe(405);
  });

  it('rejects a missing message', async () => {
    const res = await worker.fetch(post({ ...valid, message: '' }), env);
    expect(res.status).toBe(400);
  });

  it('rejects a malformed email address', async () => {
    const res = await worker.fetch(post({ ...valid, email: 'not-an-email' }), env);
    expect(res.status).toBe(400);
  });

  it('rejects a failed Turnstile check', async () => {
    global.fetch.mockResolvedValueOnce(
      new Response(JSON.stringify({ success: false }), { status: 200 }));
    const res = await worker.fetch(post(valid), env);
    expect(res.status).toBe(403);
  });

  it('sends mail when everything is valid', async () => {
    global.fetch
      .mockResolvedValueOnce(new Response(JSON.stringify({ success: true }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ id: 'abc' }), { status: 200 }));
    const res = await worker.fetch(post(valid), env);
    expect(res.status).toBe(200);
    const [url, init] = global.fetch.mock.calls[1];
    expect(url).toBe('https://api.resend.com/emails');
    expect(JSON.parse(init.body).to).toEqual(['hello@yukisrescue.org']);
  });

  it('reports an upstream failure rather than claiming success', async () => {
    global.fetch
      .mockResolvedValueOnce(new Response(JSON.stringify({ success: true }), { status: 200 }))
      .mockResolvedValueOnce(new Response('upstream boom', { status: 500 }));
    const res = await worker.fetch(post(valid), env);
    expect(res.status).toBe(502);
  });

  it('truncates an oversized message instead of relaying it whole', async () => {
    global.fetch
      .mockResolvedValueOnce(new Response(JSON.stringify({ success: true }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ id: 'abc' }), { status: 200 }));
    await worker.fetch(post({ ...valid, message: 'x'.repeat(20000) }), env);
    const body = JSON.parse(global.fetch.mock.calls[1][1].body);
    expect(body.text.length).toBeLessThan(6000);
  });
});
```

```bash
cd worker-contact && npm install && npm test
```

Expected: all seven tests fail — `src/index.js` does not exist.

- [ ] **Step 4: Implement the Worker**

Create `worker-contact/src/index.js`:

```javascript
const MAX_MESSAGE = 5000;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const json = (status, body) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  });

export default {
  async fetch(request, env) {
    if (request.method !== 'POST') return json(405, { error: 'method not allowed' });

    let data;
    try {
      data = await request.json();
    } catch {
      return json(400, { error: 'invalid JSON' });
    }

    const name = (data.name || '').trim();
    const email = (data.email || '').trim();
    const message = (data.message || '').trim();
    const token = data['cf-turnstile-response'];

    if (!name) return json(400, { error: 'name is required' });
    if (!EMAIL_RE.test(email)) return json(400, { error: 'a valid email is required' });
    if (!message) return json(400, { error: 'message is required' });

    const verify = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        secret: env.TURNSTILE_SECRET,
        response: token,
        remoteip: request.headers.get('CF-Connecting-IP') || undefined,
      }),
    });
    const outcome = await verify.json();
    if (!outcome.success) return json(403, { error: 'challenge failed' });

    const truncated = message.slice(0, MAX_MESSAGE);
    const sent = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        authorization: `Bearer ${env.RESEND_API_KEY}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        from: env.FROM_EMAIL,
        to: [env.TO_EMAIL],
        reply_to: email,
        subject: `Website contact from ${name}`,
        text: `From: ${name} <${email}>\n\n${truncated}`,
      }),
    });

    if (!sent.ok) return json(502, { error: 'could not send message' });
    return json(200, { ok: true });
  },
};
```

`reply_to` is set to the sender so replying from the mailbox reaches the enquirer. Truncation bounds what an attacker can push through the relay in a single request.

- [ ] **Step 5: Run the tests until they pass**

```bash
cd worker-contact && npm test
```

Expected: 7 passed.

- [ ] **Step 6: Set the Worker's secrets and deploy**

```bash
cd worker-contact
export CLOUDFLARE_API_TOKEN="<workers token from ~/workspace/yukis/tokens.yml>"
export CLOUDFLARE_ACCOUNT_ID="b6add582162cf7189dd6cfa6bf5f001d"
npx wrangler secret put RESEND_API_KEY
npx wrangler secret put TURNSTILE_SECRET
npx wrangler deploy --var TO_EMAIL:hello@yukisrescue.org --var FROM_EMAIL:noreply@yukisrescue.org
```

- [ ] **Step 7: Verify the endpoint rejects and accepts correctly**

```bash
curl -sS -o /dev/null -w "%{http_code}\n" https://www.yukisrescue.org/api/contact
curl -sS -X POST https://www.yukisrescue.org/api/contact \
  -H 'content-type: application/json' -d '{"name":"","email":"x","message":""}' -w "\n%{http_code}\n"
```

Expected: `405` for the GET, `400` for the invalid POST. Then submit the real form in a browser and confirm the message arrives at `hello@yukisrescue.org` — including checking the spam folder, which is where an unverified sending domain lands.

- [ ] **Step 8: Add the form to the Feedback page**

In WordPress, replace the Feedback placeholder with the form markup posting to `/api/contact`, including the Turnstile widget div and site key. Export and publish through the normal pipeline — this also serves as a second end-to-end test.

- [ ] **Step 9: Commit**

```bash
git add worker-contact/
git commit -m "feat: contact form Worker relaying to Resend

Separate Worker on a route so the assets-only site deploy stays simple.
Turnstile verified server-side; message truncated; upstream failures
reported as 502 rather than reported to the sender as success."
```

---

## Task 15: Designer handover

**Files:**
- Create: `docs/DESIGNERS.md`

**Interfaces:**
- Consumes: the working pipeline.
- Produces: documentation a designer can follow without the owner present.

- [ ] **Step 1: Write the guide**

Create `docs/DESIGNERS.md` covering, with no assumed terminal knowledge:

- Signing in: visit `control.yukisrescue.org`, enter your email, retrieve the one-time PIN, then the WordPress login.
- Editing content: Pages → edit → Update.
- Changing the design: Appearance → Editor → Styles. Colours and fonts come from the theme palette; changes apply site-wide.
- Publishing: Settings → Simply Static → Generate Static Files. The live site updates within about two minutes. **State the measured figure from Task 12 Step 5, not an estimate.**
- What you cannot do, and who to ask: installing plugins, editing theme files, adding users.
- Adding a page: create it, then add it to the Primary menu, **and** verify it appears on the live site after publishing. Note explicitly that a page linked from nowhere still exports because the sitemap is in the additional-URLs list.
- Who to contact when publishing appears not to work, and the one-line rollback the owner can perform.

- [ ] **Step 2: Verify by having a designer follow it**

Ask one designer to make a small content change using only the guide, without assistance. Any question they have to ask is a gap in the documentation — fix it rather than answering it verbally.

- [ ] **Step 3: Commit**

```bash
git add docs/DESIGNERS.md
git commit -m "docs: designer handover guide"
```

---

## Task 16: Merge and close out

- [ ] **Step 1: Confirm the full test suite passes**

```bash
./deploy/wordpress/tests/test-publish.sh
./deploy/wordpress/tests/test-backup.sh
cd worker-contact && npm test && cd ..
```

Expected: all three green. Do not proceed on a failure.

- [ ] **Step 2: Confirm production is healthy**

```bash
for p in "" about/ rescue/ feedback/; do
  printf "%-12s " "/$p"
  curl -sS -o /dev/null -w "%{http_code}\n" "https://www.yukisrescue.org/$p"
done
curl -sS -o /dev/null -w "api/contact GET: %{http_code}\n" https://www.yukisrescue.org/api/contact
```

Expected: `200` for all four pages, `405` for the GET to the API.

- [ ] **Step 3: Merge**

```bash
git checkout main && git merge --no-ff wordpress-authoring-pipeline
git push origin main
```

- [ ] **Step 4: Update the spec's deferred list**

Record what actually shipped, and carry forward: the preview environment and promotion gate, the adoptable-dogs custom post type, payment processor selection, the separate nonprofit-owned Cloudflare account, and the disposition of the `yukis-coming-soon` Worker.

```bash
git add docs/superpowers/specs/
git commit -m "docs: record shipped scope and carry deferred items forward"
git push origin main
```

---

## Self-Review

**Spec coverage.** Every spec section maps to a task: WordPress stack → 2; DNS and TLS → 2, 3; certificate → 3; access control → 4, 5; theme → 6; content model, permalinks, sitemap → 7, 8; publish pipeline → 8–11; contact form → 14; backups → 13; observability → 2; security posture → 4, 5, 12 (rollback rehearsal). The spec's "initial content shape, not a structural constraint" point is carried into Task 15's guidance on adding pages.

**Naming consistency.** Container names (`yukis-wordpress`, `yukis-mariadb`, `yukis-ddns`), volume names (`wp_db`, `wp_uploads`, `wp_themes`, `wp_export`), environment variables (`EXPORT_DIR`, `REPO_DIR`, `DEST`, `SKIP_PUSH`, `DRY_RUN`), palette slugs (`primary`, `secondary`, `surface`, `footer`, `body-text`, `white`), and script paths are used identically wherever they recur across tasks.

**Known soft spots**, called out rather than hidden:

1. **Task 10's `EXPORT_DIR` default depends on the Compose volume prefix**, which derives from the project directory name. Step 4 verifies it before use rather than trusting the default.
2. **Task 5 Step 2 may find WP-CLI absent** from the official image. The fallback is written, along with the consequence that it does not survive an image update.
3. **Task 8 is a measurement task by design.** Simply Static's free-tier paths and hooks are not assumed anywhere; Tasks 9 and 10 consume its recorded findings.
4. **`wrangler versions upload` output parsing** (Task 11) greps for a UUID. If wrangler changes its output format the step fails loudly rather than deploying the wrong version.

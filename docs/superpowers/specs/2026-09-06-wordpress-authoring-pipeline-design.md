# WordPress Authoring Pipeline for yukisrescue.org

**Date:** 2026-09-06
**Status:** Design approved, pending implementation plan
**Author:** Design session with Claude

## Problem

`orgsite` is a static site: four hand-edited HTML files deployed to Cloudflare
Workers with `wrangler`, tracked in a private GitHub repo. Publishing means
zipping the folder, running `wrangler`, and promoting through the Cloudflare
console.

Three web designers are joining. Git and `wrangler` are the wrong interface for
them. They need to edit content and design, preview the result, and publish —
without a terminal, without credentials, and without the site owner in the loop
for routine changes.

## Goals

1. Designers manage all site content and styling through a web UI.
2. Designers publish to production themselves.
3. Production stays fast, cheap, and independent of home hardware uptime.
4. Every publish is tracked and reversible.
5. The whole stack relocates to a VPS later without a rebuild.

## Non-goals

Explicitly deferred to later sprints, listed in full at the end of this
document. The largest is a preview/staging environment with a production
promotion gate — wanted, but not in this sprint.

## Architecture

Three hosts, three jobs.

```
designers ──► control.yukisrescue.org      WP authoring (node2, Cloudflare-proxied)
                      │
                      │ static export
                      ▼
              github.com/yukisrescue/orgsite   tracking + audit trail
                      │
                      │ GitHub Actions
                      ▼
              www.yukisrescue.org          Cloudflare Workers, static, production
```

Production never touches the home network. If node2, the Synology, the ISP link,
or household power fails, publishing stops but the public site stays up. This is
the central reason the design separates authoring from serving rather than
pointing `www` at a home-hosted WordPress.

WordPress is an authoring tool here, not a web server.

## 1. WordPress stack

Docker Compose on **node2**, following the existing conventions in
`observability/`: `container_name` set explicitly, `restart: unless-stopped`,
named volumes, `kickoff.sh` / `stop.sh` entry points.

- `wordpress:php8.3-apache`
- `mariadb:11`
- Three named volumes: database, uploads, themes.

**Portability is a construction constraint, not a later migration project.** No
Synology-specific bind mounts. No host paths outside the compose directory. All
configuration through environment variables in a `.env` file. Relocating to a
VPS is: `docker compose down`, rsync the volumes, `docker compose up`, repoint
DNS.

The compose file and a `.env.example` live in the `orgsite` repo. Secrets do not.

### Observability

node2 already runs promtail shipping to Loki on node1. Its scrape config uses a
`keep` allowlist regex on container names, so **the WordPress and MariaDB
containers must be added to that allowlist** or their logs are silently
discarded. Without this the stack appears to work and produces no telemetry.

## 2. DNS and TLS

- `control.yukisrescue.org` → A record to the home WAN IP, **proxied** (orange
  cloud).
- WAN IP is dynamic. DSM 7 supports Cloudflare as a native DDNS provider; the
  Synology updates the A record directly. This is preferred over CNAME-ing to
  the existing `*.synology.me` DDNS hostname, because a Cloudflare-proxied CNAME
  re-resolves on its own schedule and lags behind an IP change.
- Synology reverse proxy terminates TLS and forwards to the WordPress container
  on node2.
- Cloudflare SSL/TLS mode: **Full (strict)**.

### Certificate

The existing Cloudflare Origin CA certificate is used as-is:

- Covers `*.yukisrescue.org` and `yukisrescue.org`
- Valid until **2041-02-27**
- No renewal automation required

Origin CA certificates are trusted only by Cloudflare's proxy. This mandates the
proxied DNS record, and has the useful side effect that the home IP is never
exposed to direct traffic.

**Key handling:** `yukis.origin.cert.pem` and `yukis_pk.pem` currently sit
unencrypted in `~/workspace/yukis/`. The private key moves to a
restricted-permission location on the Synology, and is never committed to git.

If Cloudflare proxying is ever dropped, the replacement is a Let's Encrypt
wildcard via DNS-01 using a Cloudflare API token — DSM supports this natively.
Not needed now.

## 3. Access control

An internet-exposed WordPress admin is the largest attack surface in this
design, so it is not exposed.

- **Cloudflare Access** in front of `control.yukisrescue.org`. Free to 50 users.
  Designers authenticate before `wp-login.php` is reachable at all. Automated
  scanners never see a login form.
- Three designer accounts, WordPress role **Editor**: full content and Site
  Editor access, no plugin installation, no PHP editing, no user management.
- One **Administrator**: the site owner.
- 2FA on the administrator account.

## 4. Theme

A block theme whose `theme.json` encodes the design tokens of the **current**
site. The site's present appearance is reproduced exactly; what changes is that
it becomes editable.

| Token | Value |
|---|---|
| Primary / gradient | `#667eea` → `#764ba2` at 135° |
| Body text | `#333` |
| Card surface | `#f8f9fa` |
| Footer | `#2d3748` |
| Font stack | Segoe UI, Tahoma, Geneva, Verdana, sans-serif |
| Container width | `1200px` |
| Card radius | `10px` |
| Button radius | `50px` |

Today those values are duplicated across five inline `<style>` blocks. As
`theme.json` tokens they surface in the Site Editor as swatches and controls, so
restyling is UI work rather than a hunt through copy-pasted CSS.

The orphaned dark-theme `styles.css` is deleted — no page references it.

The Vercel design at `yukis-rescue-org.vercel.app` is **not** reproduced. It is
separate, unmerged work by a designer we have no source access to. That designer
brings it themselves when ready.

## 5. Content model

Four pages reproducing current state: Home, About Us, Rescue a Dog, Feedback.
The two "under construction" placeholders are carried over as-is.

The `🐾 Yuki's Rescue` text mark and `hero_banner.jpg` carry over. The hero image
is 1.5MB and is compressed during migration.

Footer organization details are a reusable block pattern, edited in one place.

**This is the initial content shape, not a structural constraint.** Designers can
add pages, split the site into routes, restructure the nav, and nest hierarchies
— all content editing, no code, no owner involvement. Nothing in the theme or
the pipeline assumes four pages.

Two settings are configured up front so a later restructure costs nothing:

- **Pretty permalinks** (`/about/`, not `/?p=12`), set before any content is
  created. Changing this after the fact churns URLs and breaks inbound links.
- **Sitemap added to the exporter's additional-URLs list.** The exporter crawls
  from the root and follows links, so a published page linked from nowhere would
  never be exported. This prevents the confusing failure where a designer
  publishes a page and cannot find it in production.

### Organization details

The footer publishes the organization's public legal identity:

- Address: 1221 Coral Reef Place, Alameda, CA
- Phone: 510.350.6924
- EIN: 41-4413466
- 501(c)(3) status line

These values originated from the Vercel site, which we have no source access to,
and were therefore held back until verified. **Confirmed accurate on 2026-09-06
by an owner of the organization.** They ship in the footer block pattern.

## 6. Publish pipeline

1. Designer edits in WordPress, clicks **Publish to site** in wp-admin.
2. Simply Static (free tier) crawls the site and writes the export to a local
   directory on node2.
3. A post-export hook commits the export to `orgsite` under a `site/` path and
   pushes.
4. GitHub Actions runs `wrangler versions upload` followed by
   `wrangler versions deploy`.
5. Live in roughly 60 seconds.

### Why git is in the path

Tracking is why the repo exists. Every publish becomes a commit carrying a full
diff, an author, and a timestamp. Rollback is `git revert` plus a workflow re-run.
With three new designers publishing unreviewed to a live nonprofit site, that
audit trail is the primary safety mechanism.

The Cloudflare deploy token lives in GitHub Actions secrets. Designers never hold
deployment credentials.

### Versioned deploys from day one

`wrangler versions upload` + `wrangler versions deploy` is used immediately, even
though both run unconditionally in this sprint. It costs nothing now and makes
the deferred preview sprint a configuration change rather than a pipeline
rewrite.

## 7. Contact form

Static pages cannot process form submissions. The Feedback page form posts to a
Cloudflare Worker at `/api/contact` on the same origin, which relays to
`hello@yukisrescue.org` (confirmed live) via Resend's free tier — 3,000 messages
per month. Cloudflare Turnstile for spam.

This keeps adopter correspondence inside infrastructure the org already
controls, with no third-party form vendor holding submissions.

Resend requires SPF and DKIM records on `yukisrescue.org` for deliverability.
Skipping domain verification means messages land in spam.

**Note:** this is the one page that does not reproduce current state — Feedback
is a placeholder today and ships as a working form.

## 8. Backups

- Nightly `mysqldump` plus an uploads tarball.
- Destination: `/media/assets/server/backup/wordpress` on the NAS.
- Synology snapshots provide versioning.
- **The restore procedure is documented and executed once before designers
  begin.** An untested backup is not a backup.

## 9. Security posture

Self-serve production publishing means a compromised WordPress instance
auto-publishes to a live, donation-collecting nonprofit site. This is recorded
here deliberately rather than discovered later.

Controls in this sprint:

- Cloudflare Access in front of wp-admin — no unauthenticated reachability
- Editor-only designer roles — no plugin or code execution paths
- Git audit trail — every publish diffable and revertible
- 2FA on the administrator account

The real fix is the deferred preview/promotion gate. Until it lands, **rollback
speed is the mitigation**, which is why the git step is non-negotiable.

## 10. Deferred to later sprints

| Item | Notes |
|---|---|
| Preview environment + production promotion gate | Wanted; explicitly deferred. Pipeline is built on versioned deploys so this slots in as configuration. |
| Adoptable-dogs listing | Custom post type. Not requested yet; adds cleanly. |
| Payment processing | Stripe / Venmo / Donorbox are client-side embeds and drop into a static page unchanged. **Plaid is not** — it requires a server-side token exchange, meaning a Worker. Org is still evaluating processors. |
| Media over 100MB | Cloudflare's free-plan proxy upload cap. Current assets are well under it. |
| Turnstile and Resend provisioning | Keys supplied when the form is wired. |

## Open items

| Item | Owner | Blocking |
|---|---|---|
| Three designer email addresses | Owner | **Yes** — for WP accounts and Access policy |
| Disposition of the `yukis-coming-soon` worker | Owner | No — retire, keep, or reuse as preview target |
| Real logo file | Owner | No — text mark until supplied |
| Turnstile + Resend keys | Owner | No — needed at form wiring |

### Resolved

| Item | Resolution |
|---|---|
| Org footer details | 2026-09-06 — confirmed accurate by an owner, ships in footer |
| Cloudflare tokens | 2026-09-07 — three account-owned tokens created and verified |
| Repo visibility | 2026-09-07 — public; Actions minutes are free |
| GitHub credential | 2026-09-07 — fine-grained PAT as `yukisrescue`, `admin: true` |
| `gh` CLI second-account login | Not required — the PAT covers workflows and secrets via `GH_TOKEN` |

### Credential handling

Credentials live in `~/workspace/yukis/` — deliberately **outside** the `orgsite`
repository, in a directory that is not a git repository at all, mode `600`:

- `zone_data.yml` — zone ID, account ID (identifiers, not secrets)
- `tokens.yml` — `dns`, `workers`, `dev` Cloudflare tokens
- `github_key.yml` — fine-grained GitHub PAT

These are **account-owned** Cloudflare tokens. They verify at
`/accounts/{account_id}/tokens/verify`, not `/user/tokens/verify`, which returns
401 for them. Noted because it looks exactly like an invalid token.

### Known risk: Cloudflare token blast radius

Cloudflare does not support per-worker scoping. `Workers Scripts: Edit` is
account-wide, so the deploy token can modify all workers on the account —
currently ten, including unrelated projects. A leaked GitHub Actions secret
therefore reaches more than this site.

This cannot be narrowed with token configuration. The correct fix is a
**separate Cloudflare account owned by the nonprofit**, which is independently
desirable for a 501(c)(3) that will hold payment integrations and outlive any
individual volunteer. Deferred, not dismissed.

### Cloudflare authorizations required

| Purpose | Scope |
|---|---|
| GitHub Actions deploy token | Account → Workers Scripts: Edit; Account → Account Settings: Read; Zone → Workers Routes: Edit |
| Synology DDNS token | Zone `yukisrescue.org` → DNS: Edit |
| Account ID + Zone ID | Read-only, dashboard |
| Zero Trust / Access application | Free tier; email OTP allowlist |
| SSL/TLS mode | Full (strict) |

Scoped tokens only. No Global API Key.

## Decision log

| Decision | Chosen | Rejected |
|---|---|---|
| Hosting | Self-hosted on node2, portable to VPS | Managed WP host, WordPress.com |
| Production topology | WP authors, Cloudflare serves static | WP serves production directly |
| Publish pipeline | WP → git → Actions → Cloudflare | Simply Static Pro direct (paid, no audit trail); local watcher script (no audit trail) |
| Publish authority | Self-serve production | Gated promotion — deferred, wanted later |
| Design source | Current `orgsite` scaffolding | Vercel design (unmerged, no source access) |
| Certificate | Existing Cloudflare Origin CA | New Let's Encrypt issuance |
| Form relay | Cloudflare Worker + Resend | Formspree and similar SaaS |

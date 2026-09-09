# Outbound mail: identity, not authentication

**2026-09-09.** A WordPress test message authenticated perfectly and still
landed in Gmail's spam folder.

    SPF:   PASS with IP 54.240.14.56
    DKIM:  PASS with domain control.yukisrescue.org
    DMARC: PASS

Because DMARC passed, `p=quarantine` never applied. Gmail filed it on its own
judgement of reputation and identity.

## Cause

The sending identity was:

    editor <editor@control.yukisrescue.org>

Three faults:

1. **No brand in the display name.** `editor` tells a filter and a human
   nothing. The organisation's name is the cheapest trust signal available.
2. **The From domain has no MX record.** `control.yukisrescue.org` cannot
   receive mail, so replies bounce — and filters penalise From addresses that
   cannot accept mail. The same is true of `ruff.`; only the root domain
   receives, via Cloudflare Email Routing.
3. **A second brand-new sending subdomain.** Reputation accrues per domain.
   Splitting traffic across `ruff.` and `control.` made both weaker.

## Fix

- Consolidated onto `ruff.yukisrescue.org`, which already carried the contact
  form's traffic.
- Display name set to the organisation's name.
- `yukis-mail-identity` must-use plugin adds
  `Reply-To: hello@yukisrescue.org`, the only domain with an MX.

## The misconception that caused it

Resend's "The email domain should match a verified sending domain" was read as
"must match `control`", the hostname WordPress is served from. It means the
domain **registered in Resend** — unrelated to where the site is hosted, and any
local part works on a verified domain.

## Rule for next time

When mail lands in spam, read the headers before changing anything. Full
SPF/DKIM/DMARC passes rule out the entire authentication layer and point at
reputation, identity, or content instead.

# DMARC report intake

Email Worker bound to `dmarc@yukisrescue.org` by an Email Routing rule. Stores
DMARC aggregate reports in the R2 bucket `yukis-dmarc`.

## Why this and not a cron job

Cloudflare DMARC Management has **no public API** to retrieve reports, so there
is nothing for a scheduled job to download. Reports must be delivered somewhere
we control. Every mailbox-based alternative requires storing IMAP credentials,
which runs against `YUKI-iywdyrrr`.

## Key layout

    reports/<YYYY>/<MM>/<DD>/<reporter>/<original-filename>

Dated by the **report's own window** (from the RFC 7489 §7.2.1.1 filename), not
receipt time — so a consumer walking `reports/2026/09/10/` gets the reports
*about* that day. Falls back to receipt date when a filename is opaque.

Each object carries `customMetadata`: `receivedAt`, `from`, `originalFilename`,
`reporter`, `policyDomain`, `windowBegin`, `windowEnd`.

## What gets written

- **Always**: the raw attachment, preserving fidelity and the original filename.
- **Additionally, for `.gz`**: the decompressed XML at the same key minus `.gz`,
  so consumers need no decompression. Most reporters (Google, Yahoo) send gzip.
- **`.zip` (Microsoft) is stored raw only.** Zip needs a real archive reader;
  adding one was not worth the dependency when the raw object is already there.
- Mail with no report attachment is recorded under `unmatched/` rather than
  dropped, so a gap in reporting is explainable rather than mysterious.

## Guards

- Rejects mail not addressed to `EXPECTED_RECIPIENT`, so a misconfigured
  catch-all cannot turn the bucket into open storage.
- Skips attachments over `MAX_ATTACHMENT_BYTES` (25 MiB default).
- A gunzip failure is logged, not fatal — the raw object remains authoritative.

## Reading the reports downstream

    wrangler r2 object get yukis-dmarc/reports/2026/09/10/google.com/<file>.xml

Or list a day:

    wrangler r2 object list yukis-dmarc --prefix reports/2026/09/10/

## Setup

1. R2 bucket `yukis-dmarc`
2. Email Routing route: `dmarc@yukisrescue.org` → this Worker
3. Add the second `rua` to the DMARC record, keeping Cloudflare's:

       v=DMARC1; p=quarantine; adkim=r; aspf=r;
       rua=mailto:12ca8531...@dmarc-reports.cloudflare.net,mailto:dmarc@yukisrescue.org;

   Order matters only for preference, not correctness. Same-domain `rua` needs
   no external authorization record.

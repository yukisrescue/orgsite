/**
 * Object-key derivation for stored DMARC reports.
 *
 * Kept separate from the email handler so it can be tested without constructing
 * MIME messages, and because the key scheme is the contract with whatever reads
 * the bucket later.
 */

/**
 * Aggregate report filenames follow RFC 7489 §7.2.1.1:
 *   <receiver-domain>!<policy-domain>!<begin-unixtime>!<end-unixtime>[!unique].xml[.gz|.zip]
 * The timestamps are the reporting window, which is the part worth preserving —
 * it is more useful than the time we happened to receive the mail.
 */
export function parseReportFilename(name) {
  const base = String(name || '').replace(/\.(gz|zip)$/i, '').replace(/\.xml$/i, '');
  const parts = base.split('!');
  if (parts.length < 4) return null;
  const begin = Number(parts[2]);
  const end = Number(parts[3]);
  if (!Number.isFinite(begin) || !Number.isFinite(end)) return null;
  return {
    reporter: parts[0],
    policyDomain: parts[1],
    begin: new Date(begin * 1000),
    end: new Date(end * 1000),
  };
}

/** Anything that could escape the key namespace or confuse a consumer. */
export function sanitizeSegment(s, fallback = 'unknown') {
  const cleaned = String(s || '')
    .toLowerCase()
    .replace(/[^a-z0-9._-]+/g, '-')
    .replace(/^[-.]+|[-.]+$/g, '')
    .slice(0, 120);
  return cleaned || fallback;
}

/**
 * reports/<YYYY>/<MM>/<DD>/<reporter>/<filename>
 *
 * Dated by the report's own window where the filename gives it, falling back to
 * receipt time. Partitioning by date keeps listings cheap as volume grows, and
 * a consumer can walk a day without scanning the bucket.
 */
export function objectKey(filename, receivedAt, fromAddress) {
  const meta = parseReportFilename(filename);
  const when = meta?.begin instanceof Date && !isNaN(meta.begin) ? meta.begin : receivedAt;
  const y = when.getUTCFullYear();
  const m = String(when.getUTCMonth() + 1).padStart(2, '0');
  const d = String(when.getUTCDate()).padStart(2, '0');
  const reporter = sanitizeSegment(
    meta?.reporter || (String(fromAddress || '').split('@')[1]) || 'unknown'
  );
  return `reports/${y}/${m}/${d}/${reporter}/${sanitizeSegment(filename, 'report.xml.gz')}`;
}

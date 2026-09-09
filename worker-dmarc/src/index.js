/**
 * DMARC aggregate report intake.
 *
 * Bound by an Email Routing rule: dmarc@yukisrescue.org -> this Worker.
 * Reports are stored in R2 so a downstream automation can read them without
 * touching a mailbox or holding IMAP credentials.
 *
 * Why an Email Worker rather than polling a mailbox: Cloudflare DMARC
 * Management has no public API to retrieve reports, and every mailbox-based
 * alternative means storing mailbox credentials somewhere — which is the thing
 * YUKI-iywdyrrr exists to eliminate.
 *
 * Both the raw attachment and, where it is gzip, the decompressed XML are
 * written. The raw copy preserves fidelity and the reporting window in its
 * filename; the XML copy saves every consumer from reimplementing
 * decompression. Zip (Microsoft) is stored raw only — see README.
 */

import PostalMime from 'postal-mime';
import { objectKey, parseReportFilename } from './keys.js';

const REPORT_NAME = /\.(xml|xml\.gz|xml\.zip|gz|zip)$/i;

async function gunzip(bytes) {
  const stream = new Response(bytes).body.pipeThrough(new DecompressionStream('gzip'));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

export default {
  async email(message, env, ctx) {
    const receivedAt = new Date();
    const maxBytes = Number(env.MAX_ATTACHMENT_BYTES || 26214400);

    // Only accept mail addressed to the intake address. Email Routing should
    // already guarantee this, but a misconfigured catch-all must not turn this
    // bucket into open storage.
    if (env.EXPECTED_RECIPIENT && message.to !== env.EXPECTED_RECIPIENT) {
      console.warn(`rejecting mail addressed to ${message.to}`);
      message.setReject('Not an accepted recipient');
      return;
    }

    let parsed;
    try {
      parsed = await PostalMime.parse(message.raw);
    } catch (err) {
      console.error('could not parse MIME', err);
      message.setReject('Unparseable message');
      return;
    }

    const attachments = (parsed.attachments || []).filter(
      (a) => REPORT_NAME.test(a.filename || '')
    );

    if (attachments.length === 0) {
      // Not a failure worth rejecting: some reporters send courtesy mail with no
      // attachment. Record it so a silent gap is explainable later.
      console.warn(`no report attachment from ${parsed.from?.address}; subject: ${parsed.subject}`);
      await env.REPORTS.put(
        `unmatched/${receivedAt.toISOString()}.json`,
        JSON.stringify({
          from: parsed.from?.address ?? null,
          subject: parsed.subject ?? null,
          receivedAt: receivedAt.toISOString(),
          reason: 'no attachment matching a DMARC report filename',
        }, null, 2),
        { httpMetadata: { contentType: 'application/json' } }
      );
      return;
    }

    const from = parsed.from?.address;
    const stored = [];

    for (const a of attachments) {
      const raw = a.content instanceof ArrayBuffer ? new Uint8Array(a.content) : a.content;
      if (raw.byteLength > maxBytes) {
        console.error(`attachment ${a.filename} is ${raw.byteLength} bytes, over the cap; skipping`);
        continue;
      }

      const key = objectKey(a.filename, receivedAt, from);
      const meta = parseReportFilename(a.filename);

      const customMetadata = {
        receivedAt: receivedAt.toISOString(),
        from: from ?? '',
        originalFilename: a.filename ?? '',
        reporter: meta?.reporter ?? '',
        policyDomain: meta?.policyDomain ?? '',
        windowBegin: meta?.begin?.toISOString() ?? '',
        windowEnd: meta?.end?.toISOString() ?? '',
      };

      await env.REPORTS.put(key, raw, {
        httpMetadata: { contentType: a.mimeType || 'application/octet-stream' },
        customMetadata,
      });
      stored.push(key);

      // Convenience copy, gzip only. Zip needs a real archive reader; the raw
      // object is still there for consumers that want it.
      if (/\.gz$/i.test(a.filename || '')) {
        try {
          const xml = await gunzip(raw);
          const xmlKey = key.replace(/\.gz$/i, '');
          await env.REPORTS.put(xmlKey, xml, {
            httpMetadata: { contentType: 'application/xml' },
            customMetadata,
          });
          stored.push(xmlKey);
        } catch (err) {
          // Not fatal: the raw object is stored and remains the source of truth.
          console.error(`could not gunzip ${a.filename}`, err);
        }
      }
    }

    if (stored.length === 0) {
      console.error('report mail received but nothing was stored');
      message.setReject('Could not store report');
      return;
    }

    console.log(`stored ${stored.length} object(s): ${stored.join(', ')}`);
  },
};

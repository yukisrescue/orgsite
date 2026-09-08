/**
 * Contact form relay for www.yukisrescue.org.
 *
 * Static pages cannot process a POST, so the Feedback form submits here.
 * Turnstile is verified server-side, then the message is relayed to the
 * organisation's inbox via Resend.
 *
 * Deliberately a separate Worker on a route: the site Worker serves static
 * assets only, and giving it a script entry point would complicate every
 * content deploy for the sake of one endpoint.
 */

const MAX_MESSAGE = 5000;
const MAX_NAME = 200;
const MAX_BODY_BYTES = 64 * 1024;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const CORS = {
  'access-control-allow-origin': 'https://www.yukisrescue.org',
  'access-control-allow-methods': 'POST, OPTIONS',
  'access-control-allow-headers': 'content-type',
};

const json = (status, body) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json', ...CORS },
  });

/** Strip CR/LF so sender-controlled text can never inject a mail header. */
const oneLine = (s) => String(s).replace(/[\r\n]+/g, ' ').trim();

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CORS });
    }
    if (request.method !== 'POST') {
      return json(405, { error: 'Method not allowed' });
    }

    // Fail closed on misconfiguration. A relay that silently stops verifying
    // its challenge is worse than one that stops working, because nobody
    // notices until the spam arrives.
    if (!env.TURNSTILE_SECRET || !env.RESEND_API_KEY) {
      console.error('contact worker misconfigured: missing TURNSTILE_SECRET or RESEND_API_KEY');
      return json(500, { error: 'The contact form is not configured. Please email us directly.' });
    }

    let raw;
    try {
      raw = await request.text();
    } catch {
      return json(400, { error: 'Could not read the request.' });
    }
    if (raw.length > MAX_BODY_BYTES) {
      return json(413, { error: 'That message is too large to send.' });
    }

    let data;
    try {
      data = JSON.parse(raw);
    } catch {
      return json(400, { error: 'Could not read the form data.' });
    }

    const name = oneLine(data?.name ?? '').slice(0, MAX_NAME);
    const email = String(data?.email ?? '').trim();
    const message = String(data?.message ?? '').trim();
    const token = data?.['cf-turnstile-response'];

    if (!name) return json(400, { error: 'Please enter your name.' });
    if (!EMAIL_RE.test(email)) return json(400, { error: 'Please enter a valid email address.' });
    if (!message) return json(400, { error: 'Please enter a message.' });

    // Verify the challenge.
    let outcome;
    try {
      const verify = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          secret: env.TURNSTILE_SECRET,
          response: token,
          remoteip: request.headers.get('CF-Connecting-IP') || undefined,
        }),
      });
      outcome = await verify.json();
    } catch (err) {
      console.error('turnstile verification failed to complete', err);
      return json(502, { error: 'Could not verify the form. Please try again.' });
    }

    if (!outcome?.success) {
      return json(403, { error: 'The form could not be verified. Please reload and try again.' });
    }

    const truncated = message.slice(0, MAX_MESSAGE);
    const wasTruncated = message.length > MAX_MESSAGE;

    let sent;
    try {
      sent = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          authorization: `Bearer ${env.RESEND_API_KEY}`,
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          from: env.FROM_EMAIL,
          to: [env.TO_EMAIL],
          // Replying from the inbox reaches the enquirer rather than the relay.
          reply_to: email,
          subject: `Website contact from ${name}`,
          text:
            `From: ${name} <${email}>\n` +
            `Sent via the contact form at www.yukisrescue.org\n\n` +
            `${truncated}` +
            (wasTruncated ? '\n\n[message truncated]' : ''),
        }),
      });
    } catch (err) {
      console.error('resend request failed', err);
      return json(502, { error: 'Could not send your message. Please try again shortly.' });
    }

    if (!sent.ok) {
      console.error('resend returned', sent.status, await sent.text().catch(() => ''));
      return json(502, { error: 'Could not send your message. Please try again shortly.' });
    }

    return json(200, { ok: true });
  },
};

import { describe, it, expect, vi, beforeEach } from 'vitest';
import worker from '../src/index.js';

const env = {
  RESEND_API_KEY: 'test-key',
  TURNSTILE_SECRET: 'test-secret',
  TO_EMAIL: 'hello@yukisrescue.org',
  FROM_EMAIL: 'noreply@send.yukisrescue.org',
};

const post = (body, headers = {}) =>
  new Request('https://www.yukisrescue.org/api/contact', {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  });

const valid = {
  name: 'Test Person',
  email: 'test@example.com',
  message: 'Is Yuki still available for adoption?',
  'cf-turnstile-response': 'token',
};

const turnstileOK = () =>
  new Response(JSON.stringify({ success: true }), { status: 200 });
const turnstileFail = () =>
  new Response(JSON.stringify({ success: false, 'error-codes': ['invalid-input-response'] }), { status: 200 });
const resendOK = () =>
  new Response(JSON.stringify({ id: 'abc' }), { status: 200 });

beforeEach(() => { global.fetch = vi.fn(); });

describe('method and shape', () => {
  it('rejects GET', async () => {
    const res = await worker.fetch(new Request('https://www.yukisrescue.org/api/contact'), env);
    expect(res.status).toBe(405);
  });

  it('answers CORS preflight', async () => {
    const res = await worker.fetch(
      new Request('https://www.yukisrescue.org/api/contact', { method: 'OPTIONS' }), env);
    expect(res.status).toBe(204);
  });

  it('rejects malformed JSON', async () => {
    const res = await worker.fetch(post('not json at all'), env);
    expect(res.status).toBe(400);
  });
});

describe('validation', () => {
  it('rejects a missing name', async () => {
    const res = await worker.fetch(post({ ...valid, name: '  ' }), env);
    expect(res.status).toBe(400);
  });

  it('rejects a missing message', async () => {
    const res = await worker.fetch(post({ ...valid, message: '' }), env);
    expect(res.status).toBe(400);
  });

  it('rejects a malformed email address', async () => {
    const res = await worker.fetch(post({ ...valid, email: 'not-an-email' }), env);
    expect(res.status).toBe(400);
  });

  it('does not call Turnstile or Resend when validation fails', async () => {
    await worker.fetch(post({ ...valid, message: '' }), env);
    expect(global.fetch).not.toHaveBeenCalled();
  });
});

describe('turnstile', () => {
  it('rejects a failed challenge with 403', async () => {
    global.fetch.mockResolvedValueOnce(turnstileFail());
    const res = await worker.fetch(post(valid), env);
    expect(res.status).toBe(403);
  });

  it('does not send mail when the challenge fails', async () => {
    global.fetch.mockResolvedValueOnce(turnstileFail());
    await worker.fetch(post(valid), env);
    expect(global.fetch).toHaveBeenCalledTimes(1);
  });

  it('passes the visitor IP to siteverify', async () => {
    global.fetch.mockResolvedValueOnce(turnstileOK()).mockResolvedValueOnce(resendOK());
    await worker.fetch(post(valid, { 'CF-Connecting-IP': '203.0.113.9' }), env);
    const body = JSON.parse(global.fetch.mock.calls[0][1].body);
    expect(body.remoteip).toBe('203.0.113.9');
    expect(body.secret).toBe('test-secret');
  });
});

describe('sending', () => {
  it('sends via Resend when everything is valid', async () => {
    global.fetch.mockResolvedValueOnce(turnstileOK()).mockResolvedValueOnce(resendOK());
    const res = await worker.fetch(post(valid), env);
    expect(res.status).toBe(200);
    const [url, init] = global.fetch.mock.calls[1];
    expect(url).toBe('https://api.resend.com/emails');
    const body = JSON.parse(init.body);
    expect(body.to).toEqual(['hello@yukisrescue.org']);
    expect(body.from).toBe('noreply@send.yukisrescue.org');
  });

  it('sets reply_to to the sender so replying reaches them', async () => {
    global.fetch.mockResolvedValueOnce(turnstileOK()).mockResolvedValueOnce(resendOK());
    await worker.fetch(post(valid), env);
    const body = JSON.parse(global.fetch.mock.calls[1][1].body);
    expect(body.reply_to).toBe('test@example.com');
  });

  it('reports upstream failure as 502 rather than claiming success', async () => {
    global.fetch.mockResolvedValueOnce(turnstileOK())
      .mockResolvedValueOnce(new Response('upstream boom', { status: 500 }));
    const res = await worker.fetch(post(valid), env);
    expect(res.status).toBe(502);
  });

  it('survives a network error from Resend', async () => {
    global.fetch.mockResolvedValueOnce(turnstileOK())
      .mockRejectedValueOnce(new Error('socket hang up'));
    const res = await worker.fetch(post(valid), env);
    expect(res.status).toBe(502);
  });

  it('truncates an oversized message instead of relaying it whole', async () => {
    global.fetch.mockResolvedValueOnce(turnstileOK()).mockResolvedValueOnce(resendOK());
    await worker.fetch(post({ ...valid, message: 'x'.repeat(50000) }), env);
    const body = JSON.parse(global.fetch.mock.calls[1][1].body);
    expect(body.text.length).toBeLessThan(6000);
  });

  it('never puts sender-controlled text in the subject header', async () => {
    global.fetch.mockResolvedValueOnce(turnstileOK()).mockResolvedValueOnce(resendOK());
    await worker.fetch(post({ ...valid, name: 'Evil\r\nBcc: victim@example.com' }), env);
    const body = JSON.parse(global.fetch.mock.calls[1][1].body);
    expect(body.subject).not.toMatch(/[\r\n]/);
  });
});

describe('misconfiguration', () => {
  it('fails closed when the Turnstile secret is absent', async () => {
    const res = await worker.fetch(post(valid), { ...env, TURNSTILE_SECRET: undefined });
    expect(res.status).toBe(500);
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('fails closed when the Resend key is absent', async () => {
    const res = await worker.fetch(post(valid), { ...env, RESEND_API_KEY: undefined });
    expect(res.status).toBe(500);
    expect(global.fetch).not.toHaveBeenCalled();
  });
});

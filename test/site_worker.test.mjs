import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import worker from '../src/index.js';

test('runs the Worker before Static Assets normalizes legacy HTML paths', async () => {
  const config = await readFile(new URL('../wrangler.jsonc', import.meta.url), 'utf8');
  assert.match(config, /"run_worker_first"\s*:\s*true/);
});

test('redirects the legacy rescue HTML URL to the home page', async () => {
  const request = new Request('https://www.yukisrescue.org/rescue.html');
  const response = await worker.fetch(request, { ASSETS: { fetch() {
    throw new Error('legacy URL must not reach static assets');
  } } });

  assert.equal(response.status, 301);
  assert.equal(response.headers.get('location'), 'https://www.yukisrescue.org/');
});

test('serves ordinary requests from the static asset binding', async () => {
  const request = new Request('https://www.yukisrescue.org/rescue/');
  const assets = { fetch(received) {
    assert.equal(received.url, request.url);
    return new Response('rescue page', { status: 200 });
  } };

  const response = await worker.fetch(request, { ASSETS: assets });
  assert.equal(response.status, 200);
  assert.equal(await response.text(), 'rescue page');
});

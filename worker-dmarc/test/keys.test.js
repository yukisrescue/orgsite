import { describe, it, expect } from 'vitest';
import { parseReportFilename, sanitizeSegment, objectKey } from '../src/keys.js';

describe('parseReportFilename', () => {
  it('parses a real Google report filename', () => {
    const m = parseReportFilename('google.com!yukisrescue.org!1757289600!1757375999.xml.gz');
    expect(m.reporter).toBe('google.com');
    expect(m.policyDomain).toBe('yukisrescue.org');
    expect(m.begin.toISOString()).toBe('2025-09-08T00:00:00.000Z');
  });

  it('parses a zip-compressed report with a unique-id segment', () => {
    const m = parseReportFilename(
      'enterprise.protection.outlook.com!yukisrescue.org!1757289600!1757375999!abc123.xml.zip');
    expect(m.reporter).toBe('enterprise.protection.outlook.com');
    expect(m.policyDomain).toBe('yukisrescue.org');
  });

  it('returns null for a filename that is not a report', () => {
    expect(parseReportFilename('invoice.pdf')).toBeNull();
    expect(parseReportFilename('')).toBeNull();
    expect(parseReportFilename(undefined)).toBeNull();
  });

  it('returns null when the timestamps are not numeric', () => {
    expect(parseReportFilename('a!b!notatime!alsonot.xml.gz')).toBeNull();
  });
});

describe('sanitizeSegment', () => {
  it('refuses path traversal', () => {
    expect(sanitizeSegment('../../etc/passwd')).not.toContain('..');
    expect(sanitizeSegment('../../etc/passwd')).not.toContain('/');
  });

  it('collapses unsafe characters', () => {
    expect(sanitizeSegment('Google Inc!!')).toBe('google-inc');
  });

  it('falls back when nothing survives', () => {
    expect(sanitizeSegment('///', 'fallback')).toBe('fallback');
    expect(sanitizeSegment('', 'fallback')).toBe('fallback');
  });

  it('bounds length', () => {
    expect(sanitizeSegment('a'.repeat(400)).length).toBeLessThanOrEqual(120);
  });
});

describe('objectKey', () => {
  const received = new Date('2026-09-10T06:00:00Z');

  it('dates the key by the report window, not receipt time', () => {
    const k = objectKey('google.com!yukisrescue.org!1757289600!1757375999.xml.gz', received, 'noreply@google.com');
    expect(k).toBe('reports/2025/09/08/google.com/google.com-yukisrescue.org-1757289600-1757375999.xml.gz');
  });

  it('falls back to receipt date and sender domain when the filename is opaque', () => {
    const k = objectKey('report.xml.gz', received, 'dmarc@yahoo.com');
    expect(k).toBe('reports/2026/09/10/yahoo.com/report.xml.gz');
  });

  it('never produces a key that escapes the prefix', () => {
    const k = objectKey('../../../etc/passwd', received, 'x@y.com');
    expect(k.startsWith('reports/')).toBe(true);
    expect(k).not.toContain('..');
  });

  it('handles a missing sender', () => {
    const k = objectKey('report.xml.gz', received, undefined);
    expect(k).toBe('reports/2026/09/10/unknown/report.xml.gz');
  });
});

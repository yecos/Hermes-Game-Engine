import { timingSafeEqual } from 'node:crypto';

export function requireApiToken(req, res) {
  const expected = process.env.HGE_API_TOKEN;
  if (!expected) {
    res.status(503).json({ error: 'HGE_API_TOKEN is not configured' });
    return false;
  }
  const provided = String(req.headers['x-hge-token'] ?? '');
  const a = Buffer.from(provided), b = Buffer.from(expected);
  const valid = a.length === b.length && timingSafeEqual(a, b);
  if (!valid) {
    res.status(401).json({ error: 'Invalid cloud token' });
    return false;
  }
  return true;
}

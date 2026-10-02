import { randomUUID } from 'node:crypto';
import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import { requireApiToken } from '../_lib/auth.js';
import { getPool } from '../_lib/db.js';

const svgPlaceholder = (prompt) => {
  const safe = String(prompt || 'AI Asset').slice(0, 36).replace(/[<>&]/g, '');
  return Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512"><rect width="512" height="512" fill="#071019"/><circle cx="256" cy="256" r="180" fill="#112535" stroke="#46e6ff" stroke-width="12"/><path d="M160 330 L256 145 L352 330 Z" fill="#b372ff" stroke="#46e6ff" stroke-width="10"/><text x="256" y="418" text-anchor="middle" font-family="Arial" font-size="25" fill="#f0f6ff">${safe}</text></svg>`);
};

async function generateRemote({ kind, prompt, name }) {
  const endpoint = process.env.HERMES_ASSET_ENDPOINT;
  if (!endpoint) return null;
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(process.env.HERMES_ASSET_TOKEN ? { authorization: `Bearer ${process.env.HERMES_ASSET_TOKEN}` } : {})
    },
    body: JSON.stringify({ kind, prompt, name, transparent: kind === 'sprite', size: '512x512' })
  });
  if (!response.ok) throw new Error(`Asset provider returned ${response.status}`);
  return response.json();
}

async function uploadBytes(key, bytes, contentType) {
  const endpoint = process.env.AWS_ENDPOINT_URL_S3;
  if (!endpoint || !process.env.AWS_ACCESS_KEY_ID || !process.env.AWS_SECRET_ACCESS_KEY) return null;
  const bucket = process.env.HGE_ASSET_BUCKET || 'hge-assets';
  const client = new S3Client({
    endpoint,
    region: process.env.AWS_REGION || 'us-east-2',
    forcePathStyle: true,
    credentials: { accessKeyId: process.env.AWS_ACCESS_KEY_ID, secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY }
  });
  await client.send(new PutObjectCommand({ Bucket: bucket, Key: key, Body: bytes, ContentType: contentType, CacheControl: 'public, max-age=31536000, immutable' }));
  return `${endpoint.replace(/\/$/, '')}/${bucket}/${key}`;
}

export default async function handler(req, res) {
  if (!requireApiToken(req, res)) return;
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  const { projectId, kind = 'sprite', prompt = '', name = '' } = req.body ?? {};
  if (!projectId || !prompt) return res.status(400).json({ error: 'projectId and prompt are required' });

  const id = `asset-${randomUUID()}`;
  let provider = 'svg-fallback', model = 'procedural-placeholder', publicUrl = null, storageKey = null, mediaType = 'image/svg+xml';

  try {
    const remote = await generateRemote({ kind, prompt, name });
    let bytes;

    if (remote) {
      provider = remote.provider ?? 'hermes';
      model = remote.model ?? 'active-model';
      mediaType = remote.mediaType ?? 'image/png';
      if (remote.base64) bytes = Buffer.from(remote.base64, 'base64');
      else if (remote.url) {
        const fetched = await fetch(remote.url);
        if (!fetched.ok) throw new Error('Could not fetch generated asset');
        bytes = Buffer.from(await fetched.arrayBuffer());
        mediaType = fetched.headers.get('content-type') ?? mediaType;
        publicUrl = remote.url;
      }
    } else {
      bytes = svgPlaceholder(prompt);
    }

    if (bytes) {
      const ext = mediaType.includes('svg') ? 'svg' : mediaType.includes('jpeg') ? 'jpg' : 'png';
      storageKey = `generated/${projectId}/${id}.${ext}`;
      publicUrl = await uploadBytes(storageKey, bytes, mediaType) ?? publicUrl ?? `data:${mediaType};base64,${bytes.toString('base64')}`;
    }

    const asset = {
      id, projectId, kind, name: name || prompt.slice(0, 48), prompt, provider, model,
      storageKey, publicUrl, status: 'ready', metadata: { mediaType }
    };

    const pool = getPool();
    await pool.query(
      `insert into hge_assets (id, project_id, kind, name, prompt, provider, model, storage_key, public_url, status, metadata, updated_at)
       values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11::jsonb,now())
       on conflict (id) do update set public_url=excluded.public_url, status=excluded.status, metadata=excluded.metadata, updated_at=now()`,
      [id, projectId, kind, asset.name, prompt, provider, model, storageKey, publicUrl, 'ready', JSON.stringify(asset.metadata)]
    );

    res.status(200).json({ asset });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
}

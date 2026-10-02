const svgFallback = (kind, prompt) => {
  const label = (prompt || kind || 'asset').slice(0, 24).replace(/[<>&]/g, '');
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512"><rect width="512" height="512" fill="#081019"/><rect x="48" y="48" width="416" height="416" rx="64" fill="#101d2a" stroke="#46e6ff" stroke-width="8"/><path d="M150 330 L256 140 L362 330 Z" fill="#b372ff" stroke="#46e6ff" stroke-width="12"/><text x="256" y="400" text-anchor="middle" font-family="system-ui" font-size="28" fill="#edf3ff">${label}</text></svg>`;
  return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
};

export class AssetGenerator {
  constructor(store, cloud) { this.store = store; this.cloud = cloud; }
  async generate({ kind = 'sprite', prompt = '', name = '' } = {}) {
    let asset;
    try {
      const response = await this.cloud.request('/assets/generate', { method: 'POST', body: JSON.stringify({ projectId: this.store.project.id, kind, prompt, name }) });
      asset = response.asset;
    } catch (error) {
      asset = {
        id: `asset-local-${globalThis.crypto?.randomUUID?.() ?? Date.now()}`,
        kind,
        name: name || prompt || `Generated ${kind}`,
        prompt,
        provider: 'local-fallback',
        model: 'svg-placeholder',
        publicUrl: svgFallback(kind, prompt),
        status: 'ready',
        metadata: { fallbackReason: error.message }
      };
    }
    return this.store.addAsset(asset);
  }
}

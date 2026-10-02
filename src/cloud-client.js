export class CloudClient {
  constructor(baseUrl = '/api') {
    this.baseUrl = baseUrl.replace(/\/$/, '');
    this.token = localStorage.getItem('hge:cloud-token') ?? '';
  }
  setToken(token) {
    this.token = token.trim();
    if (this.token) localStorage.setItem('hge:cloud-token', this.token);
    else localStorage.removeItem('hge:cloud-token');
  }
  headers(json = true) {
    const headers = {};
    if (json) headers['content-type'] = 'application/json';
    if (this.token) headers['x-hge-token'] = this.token;
    return headers;
  }
  async request(path, options = {}) {
    const response = await fetch(`${this.baseUrl}${path}`, { ...options, headers: { ...this.headers(options.body !== undefined), ...(options.headers ?? {}) } });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(payload.error ?? `Cloud API ${response.status}`);
    return payload;
  }
  health() { return this.request('/health', { method: 'GET' }); }
  listProjects() { return this.request('/projects', { method: 'GET' }); }
  loadProject(id) { return this.request(`/projects?id=${encodeURIComponent(id)}`, { method: 'GET' }); }
  saveProject(project) { return this.request('/projects', { method: 'POST', body: JSON.stringify({ project }) }); }
  logRun(run) { return this.request('/runs', { method: 'POST', body: JSON.stringify(run) }); }
}

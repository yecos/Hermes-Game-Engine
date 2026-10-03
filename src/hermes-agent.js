const DEFAULT_BRIDGE_ENDPOINT = 'http://127.0.0.1:8643/plan';

export class HermesAgent {
  constructor(store, tools, options = {}) {
    this.store = store;
    this.tools = tools;
    this.endpoint = options.endpoint ?? globalThis.HERMES_AGENT_ENDPOINT ?? localStorage.getItem('hge:hermes-endpoint') ?? '';
    this.onRun = options.onRun;
    this.connection = null;
  }

  setEndpoint(endpoint, { persist = true } = {}) {
    this.endpoint = String(endpoint || '').trim();
    this.connection = null;
    if (!persist) return;
    if (this.endpoint) localStorage.setItem('hge:hermes-endpoint', this.endpoint);
    else localStorage.removeItem('hge:hermes-endpoint');
  }

  healthUrl(endpoint = this.endpoint) {
    const value = String(endpoint || '').replace(/\/$/, '');
    if (value.endsWith('/plan')) return value.slice(0, -5) + '/health';
    try {
      const url = new URL(value);
      url.pathname = '/health';
      url.search = '';
      return url.toString();
    } catch {
      return '';
    }
  }

  async testConnection(endpoint = this.endpoint) {
    const healthUrl = this.healthUrl(endpoint);
    if (!healthUrl) throw new Error('Endpoint de Hermes inválido');
    const response = await fetch(healthUrl, {
      method: 'GET',
      cache: 'no-store'
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok || !payload.ok) {
      throw new Error(payload.error ?? `Hermes bridge: ${response.status}`);
    }
    this.connection = payload;
    return payload;
  }

  async autoDetect() {
    const candidates = [...new Set(
      [this.endpoint, DEFAULT_BRIDGE_ENDPOINT].filter(Boolean)
    )];

    for (const endpoint of candidates) {
      try {
        const info = await this.testConnection(endpoint);
        this.setEndpoint(endpoint);
        this.connection = info;
        return info;
      } catch {
        // Try the next known local bridge endpoint.
      }
    }

    if (this.endpoint) this.setEndpoint('');
    return null;
  }

  async run(prompt) {
    const startedAt = new Date().toISOString();
    let plan;
    let status = 'complete';
    let error = null;
    const results = [];

    try {
      plan = this.endpoint ? await this.remotePlan(prompt) : this.localPlan(prompt);
      for (const call of plan.calls ?? []) {
        results.push({ call, result: await this.tools.execute(call.name, call.args ?? {}) });
      }
    } catch (err) {
      status = 'error';
      error = err.message;
      throw err;
    } finally {
      this.onRun?.({
        id: `agent-${globalThis.crypto?.randomUUID?.() ?? Date.now()}`,
        projectId: this.store.project.id,
        runType: this.endpoint ? 'hermes' : 'local-planner',
        prompt,
        plan: plan?.calls ?? [],
        result: {
          message: plan?.message,
          results,
          error,
          model: plan?.model ?? this.connection?.model,
          provider: plan?.provider ?? this.connection?.provider
        },
        status,
        startedAt,
        finishedAt: new Date().toISOString()
      });
    }

    if (plan?.model || plan?.provider) {
      this.connection = {
        ...(this.connection ?? {}),
        model: plan.model ?? this.connection?.model,
        provider: plan.provider ?? this.connection?.provider
      };
    }

    return {
      message: plan?.message ?? `Ejecuté ${results.length} herramientas.`,
      calls: plan?.calls ?? [],
      results,
      model: plan?.model,
      provider: plan?.provider
    };
  }

  async remotePlan(prompt) {
    const response = await fetch(this.endpoint, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-hge-bridge': '1'
      },
      body: JSON.stringify({
        prompt,
        tools: this.tools.definitions(),
        project: this.store.snapshot(),
        activeScene: this.store.activeScene
      })
    });

    const payload = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(payload.error ?? `Hermes bridge: ${response.status}`);
    if (!Array.isArray(payload.calls)) throw new Error('Hermes devolvió un plan inválido');

    const allowed = new Set(this.tools.definitions().map((tool) => tool.name));
    if (payload.calls.length > 40) throw new Error('Hermes devolvió demasiadas acciones');
    for (const call of payload.calls) {
      if (!allowed.has(call?.name)) throw new Error(`Tool no permitida: ${call?.name ?? 'sin nombre'}`);
      if (call.args != null && (typeof call.args !== 'object' || Array.isArray(call.args))) {
        throw new Error(`Argumentos inválidos para ${call.name}`);
      }
    }

    return payload;
  }

  localPlan(raw) {
    const prompt = raw.toLowerCase().trim();
    const count = Math.min(20, Number((prompt.match(/\b(\d+)\b/) ?? [])[1] ?? 1));
    const calls = [], message = [];

    if (/nueva escena|crea.*escena|escena.*jefe|boss scene/.test(prompt)) {
      const name = /jefe|boss/.test(prompt) ? 'Boss Arena' : 'AI Scene';
      calls.push({ name: 'createScene', args: { name } });
      message.push(`Creé la escena ${name}.`);
    }
    if (/cyberpunk|cyber punk|nivel|ciudad/.test(prompt)) {
      calls.push({ name: 'setNight', args: { night: true } });
      for (let i = 0; i < 4; i++) calls.push({ name: 'createEntity', args: { type: 'enemy', name: `AI Drone ${i + 1}`, x: 620 + i * 100, y: 280 + (i % 2) * 90 } });
      for (let i = 0; i < 6; i++) calls.push({ name: 'createEntity', args: { type: 'coin', name: `Shard ${i + 1}`, x: 360 + i * 105, y: 540 - (i % 2) * 60 } });
      message.push('Construí una composición cyberpunk jugable.');
    }
    if (/enemig|enemy|dron/.test(prompt) && !/cyberpunk|cyber punk|nivel|ciudad/.test(prompt)) {
      for (let i = 0; i < count; i++) calls.push({ name: 'createEntity', args: { type: 'enemy', name: `Drone ${i + 1}`, x: 500 + i * 70, y: 300 + (i % 2) * 80 } });
      message.push(`Creé ${count} enemigo${count === 1 ? '' : 's'}.`);
    }
    if (/moneda|coin|shard|gema/.test(prompt) && !/cyberpunk|cyber punk|nivel|ciudad/.test(prompt)) {
      for (let i = 0; i < count; i++) calls.push({ name: 'createEntity', args: { type: 'coin', name: `Shard ${i + 1}`, x: 420 + i * 55, y: 520 } });
      message.push(`Creé ${count} coleccionable${count === 1 ? '' : 's'}.`);
    }
    if (/noche|night|oscuro/.test(prompt)) {
      calls.push({ name: 'setNight', args: { night: true } });
      message.push('Activé el modo noche.');
    }
    if (/día|dia|day|claro/.test(prompt)) {
      calls.push({ name: 'setNight', args: { night: false } });
      message.push('Activé el modo día.');
    }
    if (/genera.*sprite|crea.*sprite|genera.*tile|crea.*tile/.test(prompt)) {
      const kind = /tile/.test(prompt) ? 'tile' : 'sprite';
      calls.push({ name: 'generateAsset', args: { kind, prompt: raw, name: `AI ${kind}` } });
      message.push(`Solicité un ${kind} generado.`);
    }
    if (/prueba|test|juega.*nivel|revisa.*nivel/.test(prompt)) {
      calls.push({ name: 'testScene', args: { goal: raw } });
      message.push('Ejecuté el agente de pruebas sobre la escena actual.');
    }
    if (!calls.length) {
      message.push('Puedo crear escenas y entidades, generar assets, añadir behaviors y ejecutar pruebas. Conecta Hermes para planificación libre.');
    }
    return { message: message.join(' '), calls, model: 'local-planner', provider: 'browser' };
  }
}

export { DEFAULT_BRIDGE_ENDPOINT };

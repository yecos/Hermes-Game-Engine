export class HermesAgent {
  constructor(store, tools, options = {}) {
    this.store = store;
    this.tools = tools;
    this.endpoint = options.endpoint ?? globalThis.HERMES_AGENT_ENDPOINT ?? localStorage.getItem('hge:hermes-endpoint') ?? '';
    this.onRun = options.onRun;
  }

  setEndpoint(endpoint) {
    this.endpoint = endpoint.trim();
    if (this.endpoint) localStorage.setItem('hge:hermes-endpoint', this.endpoint);
    else localStorage.removeItem('hge:hermes-endpoint');
  }

  async run(prompt) {
    const startedAt = new Date().toISOString();
    const plan = this.endpoint ? await this.remotePlan(prompt).catch(() => this.localPlan(prompt)) : this.localPlan(prompt);
    const results = [];
    let status = 'complete', error = null;
    try {
      for (const call of plan.calls ?? []) results.push({ call, result: await this.tools.execute(call.name, call.args ?? {}) });
    } catch (err) {
      status = 'error'; error = err.message; throw err;
    } finally {
      this.onRun?.({
        id: `agent-${globalThis.crypto?.randomUUID?.() ?? Date.now()}`,
        projectId: this.store.project.id,
        runType: 'hermes',
        prompt,
        plan: plan.calls ?? [],
        result: { message: plan.message, results, error },
        status,
        startedAt,
        finishedAt: new Date().toISOString()
      });
    }
    return { message: plan.message ?? `Ejecuté ${results.length} herramientas.`, calls: plan.calls ?? [], results };
  }

  async remotePlan(prompt) {
    const response = await fetch(this.endpoint, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ prompt, tools: this.tools.definitions(), project: this.store.snapshot(), activeScene: this.store.activeScene })
    });
    if (!response.ok) throw new Error(`Hermes gateway: ${response.status}`);
    const payload = await response.json();
    if (!Array.isArray(payload.calls)) throw new Error('Invalid Hermes plan');
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
    if (/noche|night|oscuro/.test(prompt)) { calls.push({ name: 'setNight', args: { night: true } }); message.push('Activé el modo noche.'); }
    if (/día|dia|day|claro/.test(prompt)) { calls.push({ name: 'setNight', args: { night: false } }); message.push('Activé el modo día.'); }
    if (/genera.*sprite|crea.*sprite|genera.*tile|crea.*tile/.test(prompt)) {
      const kind = /tile/.test(prompt) ? 'tile' : 'sprite';
      calls.push({ name: 'generateAsset', args: { kind, prompt: raw, name: `AI ${kind}` } });
      message.push(`Solicité un ${kind} generado.`);
    }
    if (/prueba|test|juega.*nivel|revisa.*nivel/.test(prompt)) {
      calls.push({ name: 'testScene', args: { goal: raw } });
      message.push('Ejecuté el agente de pruebas sobre la escena actual.');
    }
    if (!calls.length) message.push('Puedo crear escenas y entidades, generar assets, añadir lógica mediante tools y ejecutar pruebas autónomas. Conecta Hermes para planificación libre.');
    return { message: message.join(' '), calls };
  }
}

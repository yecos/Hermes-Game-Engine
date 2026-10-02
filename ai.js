class HermesCopilot {
  constructor(engine,logger){this.engine=engine;this.log=logger}
  run(raw){const p=raw.toLowerCase().trim();const actions=[];const number=(p.match(/\b(\d+)\b/)||[])[1];const n=Math.min(20,Number(number||1));
    if(/cyberpunk|cyber punk|nivel|calle|ciudad/.test(p)){this.cyberLevel();actions.push('Generé una composición cyberpunk base con NPCs, obstáculos, enemigos y shards.');}
    if(/enemig|enemy|dron/.test(p)){for(let i=0;i<n;i++)this.engine.add('enemy',{name:`Drone ${String(i+1).padStart(2,'0')}`});actions.push(`Agregué ${n} enemigo${n>1?'s':''}.`)}
    if(/moneda|coin|shard|gema|recompensa/.test(p)){for(let i=0;i<n;i++)this.engine.add('coin',{name:`Data Shard ${i+1}`});actions.push(`Agregué ${n} coleccionable${n>1?'s':''}.`)}
    if(/npc|personaje secundario|vendedor/.test(p)){for(let i=0;i<n;i++)this.engine.add('npc',{name:i?`NPC ${i+1}`:'Street Fixer'});actions.push(`Creé ${n} NPC${n>1?'s':''}.`)}
    if(/objeto|obstáculo|obstaculo|caja|muro|kiosk|kiosco/.test(p)){for(let i=0;i<n;i++)this.engine.add('obstacle',{name:`Prop ${i+1}`});actions.push(`Agregué ${n} objeto${n>1?'s':''} de escenario.`)}
    if(/noche|night|oscuro/.test(p)){this.engine.world.night=true;this.engine.emit('change');actions.push('Activé iluminación nocturna.')}
    if(/día|dia|day|claro/.test(p)){this.engine.world.night=false;this.engine.emit('change');actions.push('Activé iluminación diurna.')}
    if(/rápid|rapid|velocidad|speed/.test(p)){const pl=this.engine.world.entities.find(e=>e.type==='player');if(pl){pl.speed=Math.min(650,(pl.speed||220)*1.5);this.engine.emit('change');actions.push(`Velocidad del jugador ajustada a ${Math.round(pl.speed)}.`)}}
    if(/limpia|vacía|vacia|borra.*escena|clear/.test(p)){const pl=this.engine.world.entities.find(e=>e.type==='player');this.engine.world.entities=pl?[pl]:[];this.engine.emit('change');actions.push('Limpié la escena conservando el jugador.')}
    if(!actions.length){actions.push('Entendí la intención, pero esta V0.1 todavía ejecuta un conjunto limitado de herramientas. Prueba crear enemigos, monedas, NPCs, objetos, nivel cyberpunk, modo noche o aumentar velocidad.')}
    actions.forEach(a=>this.log?.(a));return actions.join(' ')}
  cyberLevel(){const keep=this.engine.world.entities.find(e=>e.type==='player');this.engine.world.entities=keep?[keep]:[];this.engine.world.night=true;for(let i=0;i<4;i++)this.engine.add('obstacle',{name:['Neon Store','Data Terminal','Street Barrier','Tech Stall'][i],x:210+i*270,y:i%2?250:460});for(let i=0;i<3;i++)this.engine.add('enemy',{name:`Drone ${i+1}`,x:520+i*190,y:230+i*70});for(let i=0;i<6;i++)this.engine.add('coin',{name:`Shard ${i+1}`,x:330+i*120,y:570-(i%2)*80});this.engine.add('npc',{name:'Quest Fixer',x:270,y:330});this.engine.emit('change')}
}

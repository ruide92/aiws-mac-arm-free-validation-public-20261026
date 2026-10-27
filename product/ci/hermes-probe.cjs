const http = require('http');
const WS = globalThis.WebSocket || require('ws');

const sleep = ms => new Promise(r => setTimeout(r, ms));
const get = url => new Promise((resolve, reject) => {
  http.get(url, res => {
    let s = '';
    res.on('data', d => s += d);
    res.on('end', () => resolve(JSON.parse(s)));
  }).on('error', reject);
});

function connect(target) {
  const ws = new WS(target.webSocketDebuggerUrl);
  const add = (event, handler) => typeof ws.addEventListener === 'function'
    ? ws.addEventListener(event, handler) : ws.on(event, handler);
  let id = 0;
  const pending = new Map();
  add('message', raw => {
    const s = raw && raw.data !== undefined ? raw.data : raw;
    const m = JSON.parse(s.toString());
    if (!m.id || !pending.has(m.id)) return;
    const p = pending.get(m.id);
    pending.delete(m.id);
    m.error ? p.reject(new Error(JSON.stringify(m.error))) : p.resolve(m.result);
  });
  const send = (method, params = {}) => new Promise((resolve, reject) => {
    const n = ++id;
    pending.set(n, { resolve, reject });
    ws.send(JSON.stringify({ id: n, method, params }));
  });
  const ready = new Promise((resolve, reject) => {
    add('open', resolve);
    add('error', reject);
  });
  return {
    ws,
    async eval(expression) {
      await ready;
      const r = await send('Runtime.evaluate', {
        expression, returnByValue: true, awaitPromise: true
      });
      return r.result && r.result.value;
    }
  };
}

async function main() {
  let targets = [];
  for (let i = 0; i < 45; i++) {
    try {
      targets = (await get('http://127.0.0.1:9223/json/list')).filter(t => t.type === 'page');
      if (targets.length) break;
    } catch (_) {}
    await sleep(1000);
  }
  console.log('HERMES_TARGETS=' + JSON.stringify(targets.map(t => ({ url: t.url, title: t.title }))));
  if (!targets.length) throw new Error('No Hermes page target');

  const target = targets[0];
  const c = connect(target);
  const before = await c.eval(`JSON.stringify({
    title: document.title,
    url: location.href,
    text: document.body.innerText.slice(0, 1600),
    inputs: Array.from(document.querySelectorAll('input,textarea')).map(i => ({ type: i.type, placeholder: i.placeholder }))
  })`);
  console.log('HERMES_BEFORE=' + before);

  const filled = await c.eval(`(() => {
    const i = document.querySelector('input[placeholder="Your name"]');
    if (!i) return 'NO_NAME_INPUT';
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    setter.call(i, 'Mac QA');
    i.dispatchEvent(new Event('input', { bubbles: true }));
    return 'FILLED_NAME';
  })()`);
  console.log('HERMES_NAME=' + filled);

  const clicked = await c.eval(`(() => {
    const b = Array.from(document.querySelectorAll('button')).find(x => x.innerText.trim() === 'Continue');
    if (!b) return 'NO_CONTINUE';
    b.click();
    return 'CLICKED_CONTINUE';
  })()`);
  console.log('HERMES_CONTINUE=' + clicked);
  await sleep(2500);

  const after = await c.eval(`JSON.stringify({
    title: document.title,
    url: location.href,
    text: document.body.innerText.slice(0, 1600)
  })`);
  console.log('HERMES_AFTER=' + after);
  c.ws.close();
}

main().catch(err => {
  console.error('HERMES_PROBE_FAIL=' + err.message);
  process.exitCode = 1;
});

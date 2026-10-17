'use strict';
// Builds the page with DOM calls (never innerHTML), so nothing a server sends can run as markup.
const $root = document.getElementById('root');
let CSRF = '', TARGETS = [], target = '', tab = 'overview', polling = null;

function h(tag, attrs, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (k === 'class') el.className = v; else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else if (v === true) el.setAttribute(k, ''); else if (v !== false && v != null) el.setAttribute(k, v);
  }
  for (const kid of kids.flat()) if (kid != null && kid !== false) el.append(kid.nodeType ? kid : document.createTextNode(String(kid)));
  return el;
}
function toast(msg, bad) { const t = h('div', {class: 'toast' + (bad ? ' bad' : '')}, msg); document.body.append(t); setTimeout(() => t.remove(), 4500); }
async function api(path, body, method) {
  const m = method || (body === undefined ? 'GET' : 'POST');
  const res = await fetch(path, {method: m, credentials: 'same-origin', headers: {'Content-Type': 'application/json', 'X-CSRF': CSRF}, body: body === undefined ? undefined : JSON.stringify(body)});
  const d = await res.json().catch(() => ({}));
  if (res.status === 401 && path !== '/api/login') { CSRF = ''; renderLogin(); throw new Error('Signed out.'); }
  if (!res.ok) throw new Error(d.error || d.message || 'HTTP ' + res.status);
  return d;
}
const fmt = t => t ? new Date(t * 1000).toLocaleString() : '—';
const pct = n => n == null ? '—' : (n * 100).toFixed(2) + '%';
const ms = n => n == null ? '—' : Math.round(n) + ' ms';
const kv = (l, v) => h('div', {class: 'kv'}, l, h('b', {}, v));
const pill = (cls, text) => h('span', {class: 'pill ' + cls}, text);

// ------------------------------------------------------------------ sign in
function renderLogin(msg) {
  clearInterval(polling);
  const u = h('input', {placeholder: 'Username', autocomplete: 'username'}), p = h('input', {type: 'password', placeholder: 'Password', autocomplete: 'current-password'});
  const c = h('input', {placeholder: '6-digit code', inputmode: 'numeric', autocomplete: 'one-time-code', maxlength: '7'});
  const err = h('div', {class: 'err'}, msg || '');
  const go = async () => {
    try { const d = await api('/api/login', {username: u.value, password: p.value, totp: c.value}); CSRF = d.csrf; await boot(); }
    catch (e) { err.textContent = e.message; p.value = ''; c.value = ''; }
  };
  [u, p, c].forEach(i => i.addEventListener('keydown', e => { if (e.key === 'Enter') go(); }));
  $root.replaceChildren(h('div', {class: 'login card'}, h('h1', {}, 'REV ', h('b', {}, 'Games'), ' · Developer'), h('p', {class: 's'}, 'Password and a code from your authenticator app.'), u, h('br'), h('br'), p, h('br'), h('br'), c, h('br'), h('br'), h('button', {class: 'primary w100', onclick: go}, 'Sign in'), err));
}

// --------------------------------------------------------------------- shell
async function boot() {
  try { const s = await api('/api/session'); CSRF = s.csrf; TARGETS = s.targets; target = target || TARGETS[0] || ''; } catch { return renderLogin(); }
  const sel = h('select', {onchange: e => { target = e.target.value; show(tab); }}, TARGETS.map(t => h('option', {value: t, selected: t === target}, t)));
  $root.replaceChildren(
    h('header', {}, h('h1', {}, 'REV ', h('b', {}, 'Games'), ' · Developer'), TARGETS.length > 1 ? sel : null, h('span', {class: 'spacer'}),
      h('button', {class: 'small', onclick: logoutAll}, 'Sign out everywhere'), h('button', {class: 'small', onclick: async () => { await api('/api/logout', {}); renderLogin(); }}, 'Sign out')),
    h('nav', {id: 'tabs'}), h('main', {id: 'view'}));
  show('overview');
}
async function logoutAll() {
  const code = prompt('Enter a NEW authenticator code to end every session:'); if (!code) return;
  try { await api('/api/logout-everywhere', {totp: code}); renderLogin(); } catch (e) { toast(e.message, true); }
}
const TABS = {overview: 'Overview', tests: 'Tests', errors: 'Errors & crashes', controls: 'Controls', actions: 'Deploy & tools', audit: 'Audit log'};
async function show(t) {
  tab = t; clearInterval(polling);
  document.getElementById('tabs').replaceChildren(...Object.entries(TABS).map(([k, v]) => h('button', {class: k === t ? 'on' : '', onclick: () => show(k)}, v)));
  const view = document.getElementById('view');
  try { await VIEWS[t](view); } catch (e) { view.replaceChildren(h('div', {class: 'card err'}, e.message)); }
}

// -------------------------------------------------------------------- overview
function spark(points) {
  const NS = 'http://www.w3.org/2000/svg', svg = document.createElementNS(NS, 'svg');
  svg.setAttribute('class', 'spark'); svg.setAttribute('viewBox', '0 0 120 40'); svg.setAttribute('preserveAspectRatio', 'none');
  const max = Math.max(200, ...points.map(p => p.ms)), w = 120 / Math.max(1, points.length);
  points.forEach((p, i) => { const r = document.createElementNS(NS, 'rect'), bh = p.ok ? Math.max(2, p.ms / max * 38) : 38;
    r.setAttribute('x', i * w); r.setAttribute('width', Math.max(.8, w - .6)); r.setAttribute('y', 40 - bh); r.setAttribute('height', bh); r.setAttribute('fill', p.ok ? '#2ee59d' : '#ff6b6d'); svg.append(r); });
  return svg;
}
function targetCard(s) {
  const d = s.diag, m = d && d.metrics;
  return h('div', {class: 'card'},
    h('div', {class: 'row'}, h('h2', {}, s.name), pill(s.status === 'up' ? 'up' : s.status === 'down' ? 'down' : 'unknown', s.status.toUpperCase()),
      d && d.maintenance && d.maintenance.on ? pill('warning', 'MAINTENANCE') : null, h('span', {class: 'spacer'}),
      h('button', {class: 'small', onclick: async e => { e.target.disabled = true; try { await api(`/api/targets/${s.name}/probe`, {}); } catch (x) { toast(x.message, true); } show('overview'); }}, 'Check now')),
    h('div', {class: 's'}, s.url, ' · last check ', fmt(s.lastCheckAt), d ? ` · version ${d.version || '?'}${d.revision ? ' · ' + d.revision : ''}` : ''),
    s.incident ? h('div', {class: 'warn'}, `Down since ${fmt(s.incident.started)} (${s.incident.reason})`) : null,
    h('div', {class: 'grid'}, kv('Latency now', ms(s.lastMs)), kv('Uptime 24h', s.h24 ? pct(s.h24.uptime) : '—'), kv('Uptime 7d', s.d7 ? pct(s.d7.uptime) : '—'), kv('Avg / p95 24h', s.h24 ? `${ms(s.h24.avgMs)} / ${ms(s.h24.p95Ms)}` : '—'),
      m ? kv('Requests (5 min)', `${m.requests} · ${(m.errorRate * 100).toFixed(1)}% errors`) : null, m ? kv('API p50 / p95', `${ms(m.p50)} / ${ms(m.p95)}`) : null, m ? kv('Server up for', Math.round(m.uptimeSeconds / 60) + ' min') : null, d ? kv('Open crashes', d.openCrashes) : null),
    spark(s.spark),
    s.problems.length ? h('div', {}, h('h3', {}, 'Problems'), s.problems.map(p => h('div', {class: 'row'}, pill(p.severity, p.severity.toUpperCase()), h('span', {}, p.text)))) : h('div', {class: 's'}, 'No problems detected.'));
}
const VIEWS = {};
VIEWS.overview = async view => {
  const draw = async () => { const d = await api('/api/overview'); if (tab !== 'overview') return;
    view.replaceChildren(!d.targets.length ? h('div', {class: 'card'}, 'No servers yet. Copy targets.example.json to targets.json and restart the console.') : null, ...d.targets.map(targetCard),
      h('div', {class: 'card'}, h('h2', {}, 'Incidents'), d.incidents.length ? h('table', {}, h('tr', {}, ['Server', 'Started', 'Ended', 'Why'].map(x => h('th', {}, x))), d.incidents.map(i => h('tr', {}, h('td', {}, i.target), h('td', {}, fmt(i.started)), h('td', {}, i.ended ? fmt(i.ended) : pill('down', 'OPEN')), h('td', {}, i.reason)))) : h('div', {class: 's'}, 'No incidents recorded.'))); };
  await draw(); polling = setInterval(() => draw().catch(() => {}), 15000);
};

// ------------------------------------------------------------------------ tests
VIEWS.tests = async view => {
  const out = h('div'); const draw = r => out.replaceChildren(!r || !r.results ? h('div', {class: 's'}, 'Not run yet.') : h('div', {}, h('p', {}, pill(r.failed ? 'fail' : 'pass', r.failed ? `${r.failed} FAILED` : 'ALL PASSED'), ` ${r.passed} passed · ${fmt(r.at)}`),
    h('table', {}, r.results.map(c => h('tr', {}, h('td', {}, pill(c.ok ? 'pass' : 'fail', c.ok ? 'PASS' : 'FAIL')), h('td', {}, c.name), h('td', {class: 's'}, c.detail), h('td', {class: 's'}, ms(c.ms)))))));
  const btn = h('button', {class: 'primary', onclick: async () => { btn.disabled = true; btn.textContent = 'Running…'; try { draw(await api(`/api/targets/${target}/smoke`, {})); } catch (e) { toast(e.message, true); } btn.disabled = false; btn.textContent = 'Run all checks'; }}, 'Run all checks');
  view.replaceChildren(h('div', {class: 'card'}, h('h2', {}, `Live checks · ${target}`), h('p', {class: 's'}, 'Read-only checks against the running server: it answers, is fast, keeps secrets locked, and the database works. The write test saves and deletes one scratch record.'), btn, out));
  draw(await api(`/api/targets/${target}/smoke`));
};

// ----------------------------------------------------------------------- errors
VIEWS.errors = async view => {
  const [e, c] = await Promise.all([api(`/api/targets/${target}/errors`).catch(x => ({error: x.message, errors: []})), api(`/api/targets/${target}/crashes`).catch(x => ({error: x.message, crashes: []}))]);
  view.replaceChildren(
    h('div', {class: 'card'}, h('h2', {}, 'Recent server errors'), e.error ? h('div', {class: 'err'}, e.error) : null, e.errors.length ? e.errors.map(x => h('div', {class: 'card'}, h('div', {}, x.quota ? pill('critical', 'QUOTA') : pill('warning', x.type), ' ', x.path, ' ', h('span', {class: 's'}, new Date(x.at * 1000).toLocaleString())), h('div', {class: 's'}, x.message), x.trace ? h('details', {}, h('summary', {class: 's'}, 'Trace'), h('pre', {}, x.trace)) : null)) : h('div', {class: 's'}, 'None since the server started.')),
    h('div', {class: 'card'}, h('h2', {}, 'Crash groups (app + server)'), c.error ? h('div', {class: 'err'}, c.error) : null, h('p', {class: 's'}, 'Resolve them from the founder dashboard (Insights → Crashes).'),
      c.crashes.length ? h('table', {}, h('tr', {}, ['Status', 'Where', 'Error', 'Count', 'Last seen'].map(x => h('th', {}, x))), c.crashes.map(x => h('tr', {}, h('td', {}, pill(x.status === 'open' ? 'critical' : 'ok', x.status)), h('td', {}, x.source + (x.platform ? ' · ' + x.platform : '') + (x.appVersion ? ' ' + x.appVersion : '')), h('td', {}, h('b', {}, x.kind), h('div', {class: 's'}, x.message)), h('td', {}, x.count), h('td', {class: 's'}, x.lastSeenAt || '—')))) : h('div', {class: 's'}, 'No crashes. 🎉')));
};

// --------------------------------------------------------------------- controls
VIEWS.controls = async view => {
  const code = () => h('input', {class: 'w140', placeholder: 'NEW 6-digit code', inputmode: 'numeric', maxlength: '7', autocomplete: 'off'});
  const mc = code(), mscope = h('select', {}, h('option', {value: 'all'}, 'All new bets and deposits'), h('option', {value: 'live'}, 'Live money only')), mmsg = h('input', {class: 'w100', placeholder: 'Message players will see', maxlength: '200', value: "We're making things better. Back shortly."}), mconf = h('input', {class: 'w140', placeholder: 'type PAUSE', autocomplete: 'off'});
  const send = async (on, btn) => { btn.disabled = true; try { const d = await api(`/api/targets/${target}/maintenance`, {on, scope: mscope.value, message: mmsg.value, confirm: on ? mconf.value : 'RESUME', totp: mc.value}); toast(d.on ? 'Maintenance is ON' : 'Maintenance is OFF'); } catch (e) { toast(e.message, true); } btn.disabled = false; mc.value = ''; };
  const b1 = h('button', {class: 'danger', onclick: () => send(true, b1)}, 'Pause'), b2 = h('button', {onclick: () => send(false, b2)}, 'Resume');
  const mig = h('div'), gc = code(), gconf = h('input', {class: 'w140', placeholder: 'type MIGRATE', autocomplete: 'off'});
  const drawMig = async () => { const d = await api(`/api/targets/${target}/migrations`).catch(e => ({migrations: [], error: e.message})); mig.replaceChildren(d.error ? h('div', {class: 'err'}, d.error) : null, h('table', {}, d.migrations.map(m => h('tr', {}, h('td', {}, pill(m.applied ? 'ok' : 'warning', m.applied ? 'APPLIED' : 'PENDING')), h('td', {}, h('b', {}, m.id), h('div', {class: 's'}, m.description)), h('td', {class: 's'}, m.applied ? `${m.appliedAt || ''} by ${m.by || '?'} ${JSON.stringify(m.result || {})}` : ''))))); };
  const run = async apply => { try { const d = await api(`/api/targets/${target}/migrations`, {apply, confirm: gconf.value, totp: gc.value}); toast(d.report.length ? d.report.map(r => `${r.id}: ${JSON.stringify(r.result)}`).join(' · ') + (apply ? ' (applied)' : ' (dry run)') : 'Nothing pending'); } catch (e) { toast(e.message, true); } gc.value = ''; drawMig(); };
  view.replaceChildren(
    h('div', {class: 'card'}, h('h2', {}, `Maintenance mode · ${target}`), h('p', {class: 's'}, 'Stops NEW bets, rounds and deposits so you can deploy or migrate safely. Rounds already in progress can still finish and cash out; sign-in, balances and support stay open.'), h('label', {}, 'What to pause'), mscope, h('label', {}, 'Message'), mmsg,
      h('label', {}, 'Confirm'), h('div', {class: 'row'}, mconf, mc, b1, b2)),
    h('div', {class: 'card'}, h('h2', {}, 'Data migrations'), h('p', {class: 's'}, 'Versioned, repeatable-safe changes to stored data. A dry run only counts what would change. Back up first (Deploy & tools → Back up Firestore).'), mig,
      h('div', {class: 'row'}, gc, h('button', {onclick: () => run(false)}, 'Dry run'), gconf, h('button', {class: 'danger', onclick: () => run(true)}, 'Apply'))));
  drawMig();
};

// ---------------------------------------------------------------------- actions
VIEWS.actions = async view => {
  const d = await api('/api/actions'); const log = h('pre', {}, 'Run something to see its output here.'), status = h('div', {class: 's'});
  const watch = async rid => { clearInterval(polling); const tick = async () => { const r = await api('/api/runs/' + rid); log.textContent = r.output || '…'; log.scrollTop = log.scrollHeight; status.replaceChildren(pill(r.status === 'running' ? 'warning' : r.status === 'ok' ? 'ok' : 'fail', r.status.toUpperCase()), ' ', r.action); if (r.status !== 'running') clearInterval(polling); }; await tick(); polling = setInterval(() => tick().catch(() => {}), 1500); };
  const card = a => {
    const inputs = Object.fromEntries(Object.entries(a.params).map(([k, v]) => [k, h('input', {class: 'w100', value: v.default, placeholder: v.label, autocomplete: 'off'})]));
    const conf = h('input', {class: 'w140', placeholder: 'type ' + a.confirm, autocomplete: 'off'}), tc = h('input', {class: 'w140', placeholder: 'NEW 6-digit code', inputmode: 'numeric', maxlength: '7', autocomplete: 'off'});
    const btn = h('button', {class: a.danger ? 'danger' : 'primary', onclick: async () => { btn.disabled = true; try { const r = await api(`/api/actions/${a.id}/run`, {target, params: Object.fromEntries(Object.entries(inputs).map(([k, el]) => [k, el.value])), confirm: conf.value, totp: tc.value}); toast('Started'); watch(r.run); } catch (e) { toast(e.message, true); } btn.disabled = false; tc.value = ''; }}, 'Run');
    return h('div', {class: 'card'}, h('h2', {}, a.label, ' ', a.danger ? pill('critical', 'CHANGES PRODUCTION') : null), h('p', {class: 's'}, a.description), a.pre.length || a.post.length ? h('p', {class: 's'}, `Steps: ${[...a.pre.map(x => 'before: ' + x), 'run', ...a.post.map(x => 'after: ' + x)].join(' → ')} · on server "${target}"`) : null,
      Object.entries(a.params).map(([k, v]) => [h('label', {}, v.label), inputs[k]]), h('div', {class: 'row'}, conf, tc, btn));
  };
  view.replaceChildren(h('div', {class: 'warn'}, 'Each run needs a typed word and a NEW authenticator code. Commands are fixed in actions.json; the browser can only fill their named blanks, and every blank is checked against a pattern.'), ...d.actions.map(card),
    h('div', {class: 'card'}, h('h2', {}, 'Output'), status, log), h('div', {class: 'card'}, h('h2', {}, 'Recent runs'), h('table', {}, d.runs.map(r => h('tr', {}, h('td', {}, fmt(r.started)), h('td', {}, r.action), h('td', {}, r.actor), h('td', {}, pill(r.status === 'ok' ? 'ok' : r.status === 'running' ? 'warning' : 'fail', r.status)), h('td', {}, h('button', {class: 'small', onclick: () => watch(r.id)}, 'View')))))));
};

// ------------------------------------------------------------------------ audit
VIEWS.audit = async view => {
  const d = await api('/api/audit');
  view.replaceChildren(h('div', {class: 'card'}, h('h2', {}, 'Audit log ', d.chainIntact ? pill('ok', 'CHAIN INTACT') : pill('critical', 'TAMPERING DETECTED')), h('p', {class: 's'}, 'Every sign-in, failed attempt and change is recorded, each row sealed to the one before it. Editing or deleting history breaks the chain.'),
    h('table', {}, h('tr', {}, ['When', 'Who', 'From', 'What', 'Details'].map(x => h('th', {}, x))), d.rows.map(r => h('tr', {}, h('td', {}, fmt(r.at)), h('td', {}, r.actor), h('td', {class: 's'}, r.ip), h('td', {}, r.action), h('td', {class: 's'}, r.detail))))));
};

boot();

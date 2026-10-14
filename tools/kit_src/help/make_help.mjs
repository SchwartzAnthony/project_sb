// Makes the pictures for the System Builder's Help tab.
// It opens sturmball_kit.html in a fresh browser (nothing saved, nothing online), builds the
// random bottled beers example step by step, and saves a picture of each step with numbered rings.
//   node tools/kit_src/help/make_help.mjs [path/to/playwright/index.mjs]
// then run python3 tools/kit_src/build.py again so the pictures are packed into the page.
import path from 'path';import { fileURLToPath } from 'url';import { execSync } from 'child_process';
const here = path.dirname(fileURLToPath(import.meta.url));const root = path.resolve(here, '../../..');
const pw = process.argv[2] || path.join(execSync('npm root -g').toString().trim(), 'playwright/index.mjs');
const { chromium } = await import(pw);
const b = await chromium.launch({ executablePath: process.env.CHROMIUM || '/opt/pw-browsers/chromium' });
const p = await b.newPage({ viewport: { width: 1600, height: 940 } });
const errs = [];p.on('pageerror', e => errs.push(e.message));
await p.goto('file://' + path.join(root, 'sturmball_kit.html'));await p.waitForTimeout(700);
const ev = (f, a) => p.evaluate(f, a);const wait = ms => p.waitForTimeout(ms);

// ---- rings ----
const box = async sel => { const r = await p.locator(sel).first().boundingBox(); if (!r) throw new Error('no ' + sel); return r };
const card = id => ev(id => { const r = G.nodes.get(id)._g.getBoundingClientRect(); return { x: r.x, y: r.y, width: r.width, height: r.height } }, id);
const line = (a, z, f = 0.55) => ev(([a, z, f]) => { const e = G.edges.find(e => e.from == a && e.to == z && e._hit); const L = e._hit.getTotalLength(); const q = e._hit.getPointAtLength(L * f); const m = e._hit.getScreenCTM(); const x = q.x * m.a + m.e, y = q.y * m.d + m.f; return { x: x - 14, y: y - 14, width: 28, height: 28 } }, [a, z, f]);
const port = id => ev(id => { const r = G.nodes.get(id)._g.getBoundingClientRect(); return { x: r.right - 13, y: r.y + r.height / 2 - 13, width: 26, height: 26 } }, id);
const fbox = async col => { const l = p.locator(`#right [data-c="${col}"]`).first();await l.scrollIntoViewIfNeeded();await wait(50);return l.boundingBox() };
const text = async (scope, t) => box(`${scope} :text("${t}")`);
async function rings(list) {
  await ev(list => {
    document.querySelectorAll('.hring').forEach(e => e.remove());
    list.forEach(([n, r]) => {
      const pad = 4, d = document.createElement('div');d.className = 'hring';
      Object.assign(d.style, { position: 'fixed', left: (r.x - pad) + 'px', top: (r.y - pad) + 'px', width: (r.width + pad * 2) + 'px', height: (r.height + pad * 2) + 'px', border: '3px solid #e6ad3c', borderRadius: '8px', zIndex: 99999, pointerEvents: 'none', boxShadow: '0 0 0 2px #0008' });
      const k = document.createElement('div');k.textContent = n;
      Object.assign(k.style, { position: 'absolute', left: '-15px', top: '-15px', width: '26px', height: '26px', borderRadius: '50%', background: '#e6ad3c', color: '#1b1a14', font: '700 15px/26px system-ui,sans-serif', textAlign: 'center', boxShadow: '0 1px 4px #000a' });
      d.appendChild(k);document.body.appendChild(d)
    })
  }, list)
}
async function shot(name, list, clip) { await rings(list || []);await wait(120);await p.screenshot({ path: path.join(here, name + '.jpg'), type: 'jpeg', quality: 72, clip });await rings([]);console.log('shot', name) }

// ---- doing things the way Anthony would ----
const tab = v => p.click(`.tab[data-v=${v}]`);
const put = (id, x, y) => ev(([id, x, y]) => { addMine(id, true);POS[VIEW][id] = { x, y };lsSet(':pos', POS);draw() }, [id, x, y]);
const view = (x, y, k) => ev(([x, y, k]) => { cam.x = x;cam.y = y;cam.k = k;applyCam() }, [x, y, k]);
const pick = id => ev(id => { selectNone();SEL = id;highlight();inspect() }, id);
const none = () => ev(() => { selectNone();highlight();inspect();document.querySelectorAll('.pop').forEach(e => e.remove()) });
async function make(btn, name, typed) {
  await p.locator('.addbtn', { hasText: btn }).click();await p.fill('#newName', typed || name);
  if (typed) return;await p.click('#newOk');await wait(150)
}
async function field(col, val) { const f = p.locator(`#right [data-c="${col}"]`).first();await f.fill(val);await f.press('Tab');await wait(60) }
async function connect(a, z, ok = true) {
  const st = await box('#stage');await ev(([a, z, x, y]) => proposeAny(a, z, { clientX: x, clientY: y }), [a, z, st.x + 30, st.y + st.height - 330]);
  if (ok) { await p.click('#lnkOk');await wait(120) }
}

// 1. the empty screen
await shot('empty', [[1, await box('.tab[data-v=whole]')].concat([]), [1, await box('.tab[data-v=season]')], [2, await box('#search')], [3, await box('#adds')], [4, await box('#btnSave')], [5, await box('#btnChanges')], [6, await box('#btnLeft')], [6, await box('.tab[data-v=help]')], [7, await box('#play')]]);
await p.locator('#legend').scrollIntoViewIfNeeded();await wait(80);const lg = await box('#legend');await shot('shapes', [], { x: lg.x - 6, y: lg.y - 30, width: lg.width + 12, height: lg.height + 36 });

// 2. the Brewery board, finding cards
await tab('brewb');await p.fill('#search', 'bott');await wait(150);
await put('sec:bottling', 20, 120);
await view(30, 60, 0.8);
await shot('search', [[1, await box('#search')], [2, await box('#results button:has-text("Small Bottle") i')], [3, await card('sec:bottling')]]);
await p.fill('#search', '');await p.dispatchEvent('#search', 'input');
await p.locator('#left').evaluate(e => e.scrollTop = 0);
await put('res:bottle', 240, 120);await put('res:small_bottle', 460, 120);
await put('brew:plain_goalie', 700, 20);await put('brew:plain_power', 700, 120);await put('brew:plain_keeper', 700, 220);
await put('abl:PLAIN_POWER_ATK', 950, 80);await put('abl:PLAIN_POWER_DEF', 950, 160);
await view(30, 60, 0.8);await none();
const stage = await box('#stage');
await shot('lines_off', [[1, { x: stage.x + 20, y: stage.y + 60, width: stage.width - 40, height: 300 }]]);
await p.click('#btnGameLines');await wait(150);
await shot('lines_on', [[2, await box('#btnGameLines')], [2, await line('res:small_bottle', 'brew:plain_power')]]);
await shot('ex_chain', [[1, await card('sec:bottling')], [1, await card('res:small_bottle')], [2, await line('res:bottle', 'res:small_bottle')], [2, await line('res:small_bottle', 'brew:plain_goalie')]]);
await pick('brew:plain_power');
await shot('idea', [[1, await card('brew:plain_power')], [2, await line('brew:plain_power', 'abl:PLAIN_POWER_ATK')], [3, await box('#right')]]);
await ev(() => selectEdge(G.edges.find(e => e.from == 'res:small_bottle' && e.to == 'brew:plain_goalie')));await wait(80);
await shot('line_panel', [[1, await line('res:small_bottle', 'brew:plain_goalie')], [2, await box('#right .where')], [3, await box('#delE')]]);
await pick('sec:bottling');
await shot('card_panel', [[1, await card('sec:bottling')], [2, await box('#right [data-c="Takes"]')], [3, await box('#right [data-c="ID"]')]]);
await p.locator('#right [data-c="How Many"]').first().fill('lots');await p.locator('#right [data-c="How Many"]').first().press('Tab');await wait(80);
await shot('guard', [[1, await box('#right [data-c="How Many"]')], [2, await box('.toast')]]);
await wait(2600);

// 3. the example: Helles abilities
await none();await view(30, 60, 0.8);
await make('New ability', null, 'Helles: Basic Boost');
await shot('add_popup', [[1, await box('.addbtn:has-text("New ability")')], [2, await box('.pop')]]);
await p.click('#newOk');await wait(150);
await ev(() => { POS[VIEW]['abl:HELLES_BASIC_BOOST'] = { x: 950, y: 270 };lsSet(':pos', POS);draw() });
await pick('abl:HELLES_BASIC_BOOST');
await field('Effect', 'add_attack');await field('Value', '1');
await p.locator('#right').evaluate(e => e.scrollTop = 0);const tr = await fbox('Trigger'), va = await fbox('Value'), iff = await fbox('If');
await shot('ex_ability', [[1, await box('.addbtn:has-text("New ability")')], [2, tr], [2, va], [4, iff]]);
await make('New ability', 'Helles: Basic Slump');
await ev(() => { POS[VIEW]['abl:HELLES_BASIC_SLUMP'] = { x: 950, y: 350 };lsSet(':pos', POS);draw() });
await pick('abl:HELLES_BASIC_SLUMP');await field('Trigger', 'on_defend');await field('Effect', 'add_attack');await field('Value', '-1');

// the beer
await none();await make('random beer', null, 'Helles');await p.click('#newOk');await wait(120);
await shot('dup', [[3, await box('.pop')]]);
await shot('ex_dup', [[1, await box('.pop')]]);
await p.click('#newNo');
await make('random beer', 'Bottled Helles');
await ev(() => { POS[VIEW]['brew:bottled_helles'] = { x: 700, y: 310 };lsSet(':pos', POS);draw() });
await pick('brew:bottled_helles');
const pool = await fbox('Pool');
await shot('ex_beer', [[2, await card('brew:bottled_helles')], [2, pool]]);
await none();
await connect('res:small_bottle', 'brew:bottled_helles', false);
await shot('connect', [[1, await port('res:small_bottle')], [2, await box('#lnkOk')], [3, await box('#noteOk')]]);
await shot('ex_connect', [[1, await port('res:small_bottle')], [1, await card('brew:bottled_helles')], [2, await box('#lnkOk')]]);
await p.click('#lnkOk');await wait(120);
await connect('brew:bottled_helles', 'abl:HELLES_BASIC_BOOST');await connect('brew:bottled_helles', 'abl:HELLES_BASIC_SLUMP');
await pick('brew:bottled_helles');
await shot('ex_helles', [[1, await line('brew:bottled_helles', 'abl:HELLES_BASIC_BOOST')], [2, await line('brew:bottled_helles', 'abl:HELLES_BASIC_SLUMP')], [3, await fbox('Attack Ability')], [3, await fbox('Defend Ability')]]);

// Dunkles
await none();
await make('New ability', "Dunkles: Keeper's Thirst");
await ev(() => { POS[VIEW]['abl:DUNKLES_KEEPER_S_THIRST'] = { x: 950, y: 440 };lsSet(':pos', POS);draw() });
await pick('abl:DUNKLES_KEEPER_S_THIRST');await field('Target', 'own_goalie');await field('Effect', 'drain_stamina');await field('Value', '1');
await make('New ability', "Dunkles: Their Keeper's Thirst");
await ev(() => { POS[VIEW]['abl:DUNKLES_THEIR_KEEPER_S_THIRST'] = { x: 950, y: 520 };lsSet(':pos', POS);draw() });
await pick('abl:DUNKLES_THEIR_KEEPER_S_THIRST');await field('Trigger', 'on_defend');await field('Target', 'enemy_goalie');await field('Effect', 'drain_stamina');await field('Value', '1');
await make('random beer', 'Bottled Dunkles');
await ev(() => { POS[VIEW]['brew:bottled_dunkles'] = { x: 700, y: 480 };lsSet(':pos', POS);draw() });
await none();
await connect('res:small_bottle', 'brew:bottled_dunkles');await connect('brew:bottled_dunkles', 'abl:DUNKLES_KEEPER_S_THIRST');await connect('brew:bottled_dunkles', 'abl:DUNKLES_THEIR_KEEPER_S_THIRST');
await none();await view(30, 60, 0.8);
await shot('ex_dunkles', [[1, await card('abl:DUNKLES_KEEPER_S_THIRST')], [2, await card('abl:DUNKLES_THEIR_KEEPER_S_THIRST')], [3, await card('brew:bottled_dunkles')]]);

// only your beers in the bottle
await ev(() => selectEdge(G.edges.find(e => e.from == 'res:small_bottle' && e.to == 'brew:plain_goalie')));await wait(80);
await shot('ex_remove', [[1, await line('res:small_bottle', 'brew:plain_goalie')], [2, await box('#delE')]]);
await ev(() => { ['plain_goalie', 'plain_power', 'plain_keeper'].forEach(id => { const e = G.edges.find(e => e.from == 'res:small_bottle' && e.to == 'brew:' + id);if (e) removeEdge(e) });
  ['brew:plain_goalie', 'brew:plain_power', 'brew:plain_keeper', 'abl:PLAIN_POWER_ATK', 'abl:PLAIN_POWER_DEF'].forEach(id => dropMine(id)) });
await none();

// group + a board-only note line
await ev(() => { newGroupAt('Bottled beers');const g = curG()[0];Object.assign(g, { x: 680, y: 250, w: 480, h: 360 });
  saveBoardBits();selectNone();draw();drawGroups();drawNotes() });
await view(30, 60, 0.8);await none();
const gid = await ev(() => curG()[0].id);
// make it a random group, then a line into it from the bottle
await ev(gid => { selectNone();SELG = gid;highlight();inspect() }, gid);await p.click('[data-gm=random]');await wait(120);
await shot('random_group', [[1, await box('.gmodes')], [2, await box(`#gGroupTop .grp[data-id="${gid}"] .ghead`)]]);
await none();
{ const st = await box('#stage');await ev(([gid, x, y]) => proposeAny('res:small_bottle', 'grp:' + gid, { clientX: x, clientY: y }), [gid, st.x + 30, st.y + st.height - 330]) }
await shot('random_line', [[3, await port('res:small_bottle')], [4, await box('.pop p:nth-of-type(2)')], [5, await box('#lnkOk')]]);
await p.click('#lnkOk');await wait(150);await none();
const gbar = await box(`#gGroupTop .grp[data-id="${gid}"] .ghead`);
await shot('ex_group', [[1, gbar], [1, await box('#gNotes .nlabel')]]);
await shot('group', [[1, await box('#addGroup')], [2, await card('brew:bottled_dunkles')], [3, gbar], [4, await box(`#gGroupTop .grp[data-id="${gid}"] .grs`)], [5, await box(`#gGroupTop .grp[data-id="${gid}"] .port`)]]);
await shot('ex_final', [[1, await card('sec:bottling')], [1, await card('res:bottle')], [2, await line('res:small_bottle', 'brew:bottled_helles')], [3, await line('brew:bottled_helles', 'abl:HELLES_BASIC_BOOST')], [3, await line('brew:bottled_helles', 'abl:HELLES_BASIC_SLUMP')]]);
await p.click('#btnChanges');await wait(150);
await shot('ex_changes', [[2, await box('#btnChanges')], [2, await box('#chgBody')]]);
await p.click('#chgClose');

// deleting
await pick('res:bottle');await p.keyboard.press('Delete');await wait(100);
await p.locator('#delYes').click();await wait(60);
await shot('delete', [[1, await card('res:bottle')], [2, await box('#delOff')], [3, await box('#delYes')], [4, await box('#btnUndo')]]);
await p.click('#delNo');await none();

// the pretend season
await ev(() => { const d = document.querySelector('#day');d.value = 12;d.dispatchEvent(new Event('input'));d.dispatchEvent(new Event('change')) });await wait(200);
await none();
await shot('play', [[1, await box('#play')], [2, await box('#day')], [3, await card('sec:bottling')], [4, await text('#right', 'How the pretend player plays')]]);
await ev(() => { const d = document.querySelector('#day');d.value = 0;d.dispatchEvent(new Event('input')) });

// saving, tables
await p.click('#btnSave');await wait(150);
await shot('save', [[1, await box('#btnSave')], [2, await box('#svDl')], [2, await box('#svOpen')]]);
await p.click('#svClose');
await tab('tables');await wait(150);await p.selectOption('#tblPick', 'Brews');await wait(150);
await shot('tables', [[1, await box('#tblPick')], [2, await box('#grid tbody tr:nth-child(2) td:nth-child(2) input')]]);


// if this element, then this beer
await tab('brewb');await wait(150);
await ev(() => { cur().slice().forEach(id => dropMine(id));GROUPS[VIEW] = [];NOTES[VIEW] = [];saveBoardBits();draw() });
await make('random beer', 'Ember Helles');await make('random beer', 'River Dunkel');
await put('res:fire', 60, 120);await put('res:water_element', 60, 190);await put('sec:boiling', 360, 330);
await put('brew:ember_helles', 700, 120);await put('brew:river_dunkel', 700, 190);
const gids = await ev(() => { newGroupAt('Elements');const a = curG()[curG().length - 1];Object.assign(a, { x: 30, y: 70, w: 230, h: 200 });setGMode(a, 'one');
  newGroupAt('Produced Beer');const z = curG()[curG().length - 1];Object.assign(z, { x: 670, y: 70, w: 250, h: 200 });
  curN().push({ id: 'nhelp1', from: 'grp:' + a.id, to: 'sec:boiling', label: 'input' });saveBoardBits();selectNone();draw();drawGroups();drawNotes();return [a.id, z.id] });
await view(60, 80, 1);await none();
await connect('res:fire', 'brew:ember_helles', false);
await shot('if_line', [[1, await port('res:fire')], [1, await card('brew:ember_helles')], [2, await box('.pop p:nth-of-type(2)')], [3, await box('#lnkOk')]]);
await p.click('#lnkOk');await wait(120);
await connect('res:water_element', 'brew:river_dunkel');
await none();
await shot('if_board', [[1, await box(`#gGroupTop .grp[data-id="${gids[0]}"] .ghead`)], [2, await line('res:fire', 'brew:ember_helles', 0.3)], [2, await line('res:water_element', 'brew:river_dunkel', 0.3)]]);
await ev(() => selectEdge(G.edges.find(e => e.from == 'res:fire' && e.to == 'brew:ember_helles')));await wait(80);
await shot('if_panel', [[1, await line('res:fire', 'brew:ember_helles', 0.3)], [2, await box('#right .hint')]]);

// pick lists: the words a column takes
await none();await make('New ability', 'Helles Slump');
await ev(() => { POS[VIEW]['abl:HELLES_SLUMP'] = { x: 360, y: 500 };lsSet(':pos', POS);draw();selectNone();SEL = 'abl:HELLES_SLUMP';highlight();inspect() });
await p.click('#right [data-pick="Effect"]');await wait(100);await p.fill('.pk-q', 'attack');await wait(120);
await p.locator('#right .picker').scrollIntoViewIfNeeded();await wait(80);
await shot('pick', [[1, await box('#right [data-pick="Effect"]')], [2, await box('#right .pk-q')], [3, await box('.pk-opt:has-text("add_attack") button:has-text("Take away")')]]);

// compare: the game's achievements next to your own board
await none();await tab('ach');await wait(150);
await ev(() => { CARDS.ach = ['ach:first_win', 'ach:treble'];saveMine();draw() });
await p.click('#btnCompare');await wait(300);await none();await ev(() => fit());await wait(200);
await shot('compare', [[1, await box('#btnCompare')], [2, await box('#right h2')], [3, await box('#cmpAdd')]]);
console.log('page errors', errs);await b.close();

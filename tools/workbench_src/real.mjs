import { chromium } from 'playwright';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
// RUN FROM ANYWHERE: the page and the data folder are found from this file's
// own place in the project. Override with WB_HTML / WB_DATA if you must.
const HERE = path.dirname(fileURLToPath(import.meta.url));
const PROJECT = path.resolve(HERE, '..', '..');
const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
const p = await b.newPage({ viewport: { width: 1500, height: 980 } });
const errs = [];
p.on('pageerror', e => errs.push('PAGEERROR: ' + e.message));
p.on('console', m => { if (m.type() === 'error') errs.push('CONSOLE: ' + m.text()); });
await p.goto('file://' + (process.env.WB_HTML || path.join(PROJECT, 'sturmball_workbench.html')));
await p.waitForTimeout(600);

// feed it the REAL data folder
const dir = process.env.WB_DATA || path.join(PROJECT, 'data');
const payload = {};
for (const f of fs.readdirSync(dir)) {
  if (f.toLowerCase().endsWith('.csv')) payload[f] = fs.readFileSync(dir + '/' + f, 'utf8');
}
const report = await p.evaluate((files) => {
  for (const [name, text] of Object.entries(files)) ingest(name, text);
  SAMPLE = false; CUR = Object.keys(DATA)[0];
  save(); paintRail(); paintTable(); check();
  return { files: Object.keys(DATA).length, probs: PROBS.map(x => `${x.file} ${x.row+2} [${x.col}] ${x.msg}`) };
}, payload);
console.log('loaded', report.files, 'files |', report.probs.length, 'problems');
report.probs.forEach(s => console.log('  ', s));

// click a rail page by the label it shows, not by position
async function page(label) {
  const items = await p.$$('#special .fitem');
  for (const it of items) {
    const t = await it.$eval('.fn', e => e.textContent);
    if (t === label) { await it.click(); await p.waitForTimeout(450); return true; }
  }
  throw new Error('no rail page called ' + label);
}

await page('Where things go');
const wants = await p.$$eval('.want .nm', els => els.length);
console.log('assets wanted:', wants);
await p.screenshot({ path: 'shot_assets_real.png' });

// ---- the new Art & sizes page ----
await page('Art & sizes');
const art = await p.evaluate(() => ({
  groups: ART_GROUPS.length,
  kinds: artRowCount(),
  tables: document.querySelectorAll('#wrap table.spec').length,
  ticks: document.querySelectorAll('#wrap .spec input[type=checkbox]').length,
  warns: document.querySelectorAll('#wrap .warnbox').length,
  dupIds: (() => { const s = new Set(), d = []; ART_GROUPS.forEach(g => (g.rows || []).forEach(r => { if (s.has(r.id)) d.push(r.id); s.add(r.id); })); return d; })(),
  missing: (() => { const m = []; ART_GROUPS.forEach(g => (g.rows || []).forEach(r => { ['what', 'drawn', 'make', 'fit', 'from'].forEach(k => { if (!r[k]) m.push(r.id + '.' + k); }); })); return m; })(),
}));
console.log('art page:', JSON.stringify(art));
await p.screenshot({ path: 'shot_art.png', fullPage: true });
// tick one and make sure it reaches the rail count
await p.click('#wrap .spec input[type=checkbox]');
await p.waitForTimeout(250);
const railArt = await p.evaluate(() => {
  const its = [...document.querySelectorAll('#special .fitem')];
  const one = its.find(i => i.querySelector('.fn').textContent === 'Art & sizes');
  return one.querySelector('.fc').textContent;
});
console.log('rail count after one tick:', railArt);

// ---- the new Handbook page ----
await page('Handbook');
const book = await p.evaluate(() => ({
  cards: document.querySelectorAll('#wrap .cheat').length,
  rows: document.querySelectorAll('#wrap .cheat table tr').length,
}));
console.log('handbook:', JSON.stringify(book));
await p.screenshot({ path: 'shot_book.png', fullPage: true });

await page('Reference');
await p.waitForTimeout(200);

// ---- the Keywords page ----
await page('Keywords');
const words = await p.evaluate(() => ({
  count: keywordCount(),
  families: [...new Set(keywordRows().map(r => r.family))].length,
  planned: keywordRows().filter(r => r.status !== 'live').length,
}));
console.log('keywords:', JSON.stringify(words));

// back to a data file, to prove nothing on the ordinary pages moved
const btns = await p.$$('#files .fitem');
await btns[2].click();
await p.waitForTimeout(300);
await p.screenshot({ path: 'shot_table_real.png' });

console.log(errs.length ? errs.join('\n') : 'NO JS ERRORS');
await b.close();
